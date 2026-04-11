//
//  SyncPreparedTrackBuilder.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import AmMusicDatabaseKit
@preconcurrency import AVFoundation
import Foundation

nonisolated struct PreparedTransferBatch {
    let manifest: SyncManifest
    let filesByTrackID: [String: URL]
    let cleanupDirectoryURL: URL

    var preparedURLs: [URL] {
        manifest.entries.compactMap { filesByTrackID[$0.trackID] }
    }
}

final nonisolated class SyncPreparedTrackBuilder: @unchecked Sendable {
    private let paths: LibraryPaths
    private let lyricsCacheStore: LyricsCacheStore?
    private let apiClient: APIClient?
    private let fileManager: FileManager

    init(
        paths: LibraryPaths,
        lyricsCacheStore: LyricsCacheStore? = nil,
        apiClient: APIClient? = nil,
        fileManager: FileManager = .default,
    ) {
        self.paths = paths
        self.lyricsCacheStore = lyricsCacheStore
        self.apiClient = apiClient
        self.fileManager = fileManager
    }

    func prepareBatch(
        deviceName: String,
        tracks: [AudioTrackRecord],
        progress: (@MainActor (_ current: Int, _ total: Int) -> Void)? = nil,
    ) async throws -> PreparedTransferBatch {
        guard !tracks.isEmpty else {
            throw SyncTransferError.noPreparedSongs
        }

        let cleanupDirectoryURL = try makeCleanupDirectory()
        var entries: [SyncManifestEntry] = []
        var filesByTrackID: [String: URL] = [:]
        var usedFileNames = Set<String>()

        for (index, track) in tracks.enumerated() {
            await progress?(index + 1, tracks.count)

            let item = track.exportItem(paths: paths)
            do {
                let prepared = try prepareItemForTransfer(
                    item,
                    durationSeconds: track.durationSeconds,
                    cleanupDirectoryURL: cleanupDirectoryURL,
                    usedFileNames: &usedFileNames,
                )
                entries.append(prepared.entry)
                filesByTrackID[prepared.entry.trackID] = prepared.fileURL
            } catch {
                AppLog.warning(
                    self,
                    "prepareBatch skipped trackID=\(item.trackID) title='\(sanitizedLogText(item.title, maxLength: 80))' error=\(error.localizedDescription)",
                )
            }
        }

        guard !entries.isEmpty else {
            cleanup(directoryURL: cleanupDirectoryURL)
            throw SyncTransferError.noPreparedSongs
        }

        let manifest = SyncManifest(deviceName: deviceName, entries: entries)
        AppLog.info(self, "prepareBatch prepared \(entries.count)/\(tracks.count) track(s)")
        return PreparedTransferBatch(
            manifest: manifest,
            filesByTrackID: filesByTrackID,
            cleanupDirectoryURL: cleanupDirectoryURL,
        )
    }

    func prepareBatch(
        deviceName: String,
        items: [SongExportItem],
        progress: (@MainActor (_ current: Int, _ total: Int) -> Void)? = nil,
    ) async throws -> PreparedTransferBatch {
        guard !items.isEmpty else {
            throw SyncTransferError.noPreparedSongs
        }

        let cleanupDirectoryURL = try makeCleanupDirectory()
        var entries: [SyncManifestEntry] = []
        var filesByTrackID: [String: URL] = [:]
        var usedFileNames = Set<String>()

        for (index, item) in items.enumerated() {
            await progress?(index + 1, items.count)

            do {
                let prepared = try await prepareItemWithMetadata(
                    item,
                    cleanupDirectoryURL: cleanupDirectoryURL,
                    usedFileNames: &usedFileNames,
                )
                entries.append(prepared.entry)
                filesByTrackID[prepared.entry.trackID] = prepared.fileURL
            } catch {
                AppLog.warning(
                    self,
                    "prepareBatch skipped trackID=\(item.trackID) title='\(sanitizedLogText(item.title, maxLength: 80))' error=\(error.localizedDescription)",
                )
            }
        }

        guard !entries.isEmpty else {
            cleanup(directoryURL: cleanupDirectoryURL)
            throw SyncTransferError.noPreparedSongs
        }

        let manifest = SyncManifest(deviceName: deviceName, entries: entries)
        AppLog.info(self, "prepareBatch prepared \(entries.count)/\(items.count) track(s)")
        return PreparedTransferBatch(
            manifest: manifest,
            filesByTrackID: filesByTrackID,
            cleanupDirectoryURL: cleanupDirectoryURL,
        )
    }

    func cleanup(batch: PreparedTransferBatch?) {
        guard let batch else {
            return
        }
        cleanup(directoryURL: batch.cleanupDirectoryURL)
    }
}

private nonisolated extension SyncPreparedTrackBuilder {
    nonisolated struct PreparedTrack {
        let entry: SyncManifestEntry
        let fileURL: URL
    }

    nonisolated func prepareItemWithMetadata(
        _ item: SongExportItem,
        cleanupDirectoryURL: URL,
        usedFileNames: inout Set<String>,
    ) async throws -> PreparedTrack {
        let destinationURL = cleanupDirectoryURL.appendingPathComponent(
            uniqueFileName(for: item, usedFileNames: &usedFileNames),
        )
        try copyExportSource(item.sourceURL, to: destinationURL)

        var exportInfo = ExportMetadataProcessor.ExportInfo(
            trackID: item.trackID,
            albumID: item.albumID,
            artworkURL: item.artworkURL,
            lyrics: lyricsCacheStore?.lyrics(for: item.trackID),
            title: item.title,
            artistName: item.artistName,
            albumName: item.albumName,
        )
        try ExportMetadataProcessor.validateExportInfo(exportInfo)

        if exportInfo.artworkData == nil,
           let artworkURL = exportInfo.artworkURL
        {
            exportInfo.artworkData = try? await DownloadArtworkProcessor.cachedArtworkData(
                trackID: item.trackID,
                artworkURL: artworkURL,
                apiClient: apiClient,
                locations: paths,
                session: .shared,
            )
        }

        do {
            try await ExportMetadataProcessor.embedExportMetadata(exportInfo, into: destinationURL)
            try await ExportMetadataProcessor.verifyEmbeddedMetadata(
                in: destinationURL,
                expectedTrackID: item.trackID,
            )
        } catch {
            cleanupPreparedFile(at: destinationURL)
            throw error
        }

        let attributes = try fileManager.attributesOfItem(atPath: destinationURL.path)
        let fileSizeBytes = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let asset = AVURLAsset(url: destinationURL)
        let duration = try await asset.load(.duration)
        let entry = SyncManifestEntry(
            trackID: item.trackID,
            albumID: item.albumID,
            title: item.title,
            artistName: item.artistName,
            albumTitle: item.albumName ?? String(localized: "Unknown Album"),
            durationSeconds: max(duration.seconds, 0),
            fileSizeBytes: fileSizeBytes,
            fileExtension: destinationURL.pathExtension.lowercased(),
        )
        return PreparedTrack(entry: entry, fileURL: destinationURL)
    }

    nonisolated func prepareItemForTransfer(
        _ item: SongExportItem,
        durationSeconds: Double,
        cleanupDirectoryURL: URL,
        usedFileNames: inout Set<String>,
    ) throws -> PreparedTrack {
        let destinationURL = cleanupDirectoryURL.appendingPathComponent(
            uniqueFileName(for: item, usedFileNames: &usedFileNames),
        )
        try copyExportSource(item.sourceURL, to: destinationURL)

        let attributes = try fileManager.attributesOfItem(atPath: destinationURL.path)
        let fileSizeBytes = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let entry = SyncManifestEntry(
            trackID: item.trackID,
            albumID: item.albumID,
            title: item.title,
            artistName: item.artistName,
            albumTitle: item.albumName ?? String(localized: "Unknown Album"),
            durationSeconds: max(durationSeconds, 0),
            fileSizeBytes: fileSizeBytes,
            fileExtension: destinationURL.pathExtension.lowercased(),
        )
        return PreparedTrack(entry: entry, fileURL: destinationURL)
    }

    nonisolated func makeCleanupDirectory() throws -> URL {
        let directoryURL = fileManager.temporaryDirectory
            .appendingPathComponent("am-transfer-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
        )
        return directoryURL
    }

    nonisolated func copyExportSource(_ sourceURL: URL, to destinationURL: URL) throws {
        do {
            try fileManager.linkItem(at: sourceURL, to: destinationURL)
        } catch {
            do {
                try fileManager.copyItem(at: sourceURL, to: destinationURL)
            } catch {
                throw error
            }
        }
    }

    nonisolated func cleanupPreparedFile(at fileURL: URL) {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return
        }
        do {
            try fileManager.removeItem(at: fileURL)
        } catch {
            AppLog.error(self, "cleanupPreparedFile failed path=\(fileURL.path) error=\(error.localizedDescription)")
        }
    }

    nonisolated func cleanup(directoryURL: URL) {
        guard fileManager.fileExists(atPath: directoryURL.path) else {
            return
        }
        do {
            try fileManager.removeItem(at: directoryURL)
        } catch {
            AppLog.error(self, "cleanup failed path=\(directoryURL.path) error=\(error.localizedDescription)")
        }
    }

    nonisolated func uniqueFileName(
        for item: SongExportItem,
        usedFileNames: inout Set<String>,
    ) -> String {
        let baseName = item.preferredFileBaseName
        let `extension` = item.sourceURL.pathExtension.nilIfEmpty ?? "m4a"
        let sanitizedBaseName = sanitizeDisplayFileName(baseName, fallback: item.trackID)

        var candidate = "\(sanitizedBaseName).\(`extension`)"
        var suffix = 2
        while usedFileNames.contains(candidate.lowercased()) {
            candidate = "\(sanitizedBaseName) \(suffix).\(`extension`)"
            suffix += 1
        }
        usedFileNames.insert(candidate.lowercased())
        return candidate
    }
}
