//
//  LibraryScanner.swift
//  MuseAmpDatabaseKit
//
//  Created by @Lakr233 on 2026/04/11.
//

import Foundation

struct LibraryScanner {
    struct RebuildResult {
        let scanned: Int
        let upserted: Int
        let deleted: Int
        let removedInvalidFiles: [RemovedInvalidFile]
        let transientFailureRelativePaths: [String]
    }

    let paths: LibraryPaths
    let indexStore: IndexStore
    let cacheCoordinator: CacheCoordinator
    let fileManager: LibraryFileManager
    let dependencies: RuntimeDependencies
    let logger: DatabaseLogger

    func discoverAudioFiles() -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: paths.audioDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles],
        ) else {
            return []
        }

        var urls: [URL] = []
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                continue
            }
            urls.append(url)
        }
        return urls
    }

    func validatePath(_ relativePath: String) -> Bool {
        let pattern = #"^[^/]+/[^/]+\.[A-Za-z0-9]+$"#
        return relativePath.range(of: pattern, options: .regularExpression) != nil
    }

    func rebuildIndexFromDisk(
        pruneInvalidFiles: Bool,
        forceArtwork: Bool = false,
        progressCallback: (@Sendable (Int, Int) -> Void)? = nil,
    ) async throws -> RebuildResult {
        if forceArtwork {
            cacheCoordinator.clearArtworkCache()
        }
        let snapshot = try indexStore.trackSnapshotByRelativePath()
        let audioFiles = discoverAudioFiles()
        var seenRelativePaths = Set<String>()
        var upserts: [AudioTrackRecord] = []
        var removedInvalidFiles: [RemovedInvalidFile] = []
        var transientFailureRelativePaths: [String] = []

        func recordInvalidFile(_ relativePath: String, reason: String) {
            let existing = snapshot[relativePath]
            removedInvalidFiles.append(RemovedInvalidFile(
                relativePath: relativePath,
                trackID: existing?.trackID,
                title: existing?.title,
                artistName: existing?.artistName,
                reason: reason,
            ))
        }

        func pruneInvalidFileIfRequested(_ fileURL: URL) {
            guard pruneInvalidFiles else {
                return
            }
            try? FileManager.default.removeItem(at: fileURL)
            try? fileManager.removeEmptyDirectoryIfNeeded(fileURL.deletingLastPathComponent())
        }

        let totalFiles = audioFiles.count
        for (fileIndex, fileURL) in audioFiles.enumerated() {
            progressCallback?(fileIndex, totalFiles)
            let relativePath = paths.relativeAudioPath(for: fileURL)
            seenRelativePaths.insert(relativePath)

            if relativePath.hasSuffix(".tmp") {
                recordInvalidFile(
                    relativePath,
                    reason: String(localized: "Leftover temporary download file", bundle: .module),
                )
                pruneInvalidFileIfRequested(fileURL)
                continue
            }
            guard validatePath(relativePath) else {
                recordInvalidFile(
                    relativePath,
                    reason: String(localized: "File is outside the expected album folder layout", bundle: .module),
                )
                pruneInvalidFileIfRequested(fileURL)
                continue
            }

            let components = relativePath.split(separator: "/", maxSplits: 1).map(String.init)
            let albumID = components[0]
            let fileName = components[1]
            let fileExtension = URL(fileURLWithPath: fileName).pathExtension.lowercased()
            let trackID = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent

            let attributes: [FileAttributeKey: Any]
            do {
                attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            } catch {
                logger.warning("LibraryScanner", "attributes read failed, keeping file relativePath=\(relativePath) error=\(error.localizedDescription)")
                transientFailureRelativePaths.append(relativePath)
                continue
            }
            let fileSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            let modifiedAt = attributes[.modificationDate] as? Date ?? .init(timeIntervalSince1970: 0)

            if let existing = snapshot[relativePath],
               existing.fileSizeBytes == fileSize,
               abs(existing.fileModifiedAt.timeIntervalSince(modifiedAt)) < 0.5
            {
                if forceArtwork {
                    do {
                        let artwork = try await dependencies.inspectAudioFile(fileURL).embeddedArtwork
                        if let artwork {
                            try? cacheCoordinator.writeArtwork(data: artwork, trackID: trackID)
                        }
                    } catch let error as AudioFileValidationError {
                        // The file kept its size and mtime but is no longer
                        // readable: in-place corruption the fast path would
                        // otherwise hide forever.
                        logger.warning("LibraryScanner", "indexed file failed revalidation relativePath=\(relativePath) error=\(error.localizedDescription)")
                        recordInvalidFile(relativePath, reason: error.localizedDescription)
                        pruneInvalidFileIfRequested(fileURL)
                    } catch {
                        logger.warning("LibraryScanner", "forceArtwork re-extract failed relativePath=\(relativePath) error=\(error.localizedDescription)")
                    }
                }
                continue
            }

            do {
                let inspection = try await dependencies.inspectAudioFile(fileURL)
                let metadata = inspection.metadata
                let record = AudioTrackRecord(
                    trackID: trackID,
                    albumID: albumID,
                    fileExtension: fileExtension,
                    relativePath: relativePath,
                    fileSizeBytes: fileSize,
                    fileModifiedAt: modifiedAt,
                    durationSeconds: metadata.durationSeconds ?? 0,
                    title: metadata.title,
                    artistName: metadata.artistName,
                    albumTitle: metadata.albumTitle,
                    albumArtistName: metadata.albumArtistName,
                    trackNumber: metadata.trackNumber,
                    discNumber: metadata.discNumber,
                    genreName: metadata.genreName,
                    composerName: metadata.composerName,
                    releaseDate: metadata.releaseDate,
                    hasEmbeddedLyrics: metadata.lyrics.nilIfEmpty != nil,
                    hasEmbeddedArtwork: inspection.embeddedArtwork != nil,
                    sourceKind: metadata.sourceKind,
                    createdAt: snapshot[relativePath]?.createdAt ?? .init(),
                    updatedAt: .init(),
                )
                upserts.append(record)
                if let artwork = inspection.embeddedArtwork {
                    try? cacheCoordinator.writeArtwork(data: artwork, trackID: trackID)
                }
                if let lyrics = metadata.lyrics.nilIfEmpty {
                    try? cacheCoordinator.writeLyrics(text: lyrics, trackID: trackID)
                }
            } catch let error as AudioFileValidationError {
                logger.warning("LibraryScanner", "audio file failed validation relativePath=\(relativePath) error=\(error.localizedDescription)")
                recordInvalidFile(relativePath, reason: error.localizedDescription)
                pruneInvalidFileIfRequested(fileURL)
            } catch {
                // Transient failure (I/O, file protection, cancellation): keep
                // the file and any existing index row; a later rebuild retries.
                logger.warning("LibraryScanner", "inspectAudioFile transient failure, keeping file relativePath=\(relativePath) error=\(error.localizedDescription)")
                transientFailureRelativePaths.append(relativePath)
            }
        }

        try indexStore.upsertTracks(upserts)
        let invalidRelativePaths = Set(removedInvalidFiles.map(\.relativePath))
        let deletedPaths = snapshot.keys.filter { !seenRelativePaths.contains($0) || invalidRelativePaths.contains($0) }
        try indexStore.deleteTracks(relativePaths: deletedPaths)
        let validTrackIDs = try indexStore.trackIDs()
        try cacheCoordinator.pruneOrphanArtwork(validTrackIDs: validTrackIDs)
        try cacheCoordinator.pruneOrphanLyrics(validTrackIDs: validTrackIDs)
        removeEmptyAlbumDirectories()

        return RebuildResult(
            scanned: audioFiles.count,
            upserted: upserts.count,
            deleted: deletedPaths.count,
            removedInvalidFiles: removedInvalidFiles,
            transientFailureRelativePaths: transientFailureRelativePaths,
        )
    }

    private func removeEmptyAlbumDirectories() {
        guard let directories = try? FileManager.default.contentsOfDirectory(
            at: paths.audioDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles],
        ) else {
            return
        }

        for directory in directories {
            guard directory.hasDirectoryPath else {
                continue
            }
            if let contents = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
            ), contents.isEmpty {
                try? FileManager.default.removeItem(at: directory)
            }
        }
    }
}
