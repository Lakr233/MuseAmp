//
//  SyncPreparedTrackBuilder.swift
//  MuseAmp
//
//  Created by @Lakr233 on 2026/04/11.
//

@preconcurrency import AVFoundation
import Foundation
import MuseAmpDatabaseKit

nonisolated struct PreparedTransferBatch {
    let manifest: SyncManifest
    let filesByTrackID: [String: URL]
    let companionFilesByTrackID: [String: [URL]]
    let cleanupDirectoryURL: URL

    var preparedURLs: [URL] {
        manifest.entries.flatMap { entry in
            var urls: [URL] = []
            if let audioURL = filesByTrackID[entry.trackID] {
                urls.append(audioURL)
            }
            urls.append(contentsOf: companionFilesByTrackID[entry.trackID] ?? [])
            return urls
        }
    }
}

final nonisolated class SyncPreparedTrackBuilder: @unchecked Sendable {
    let paths: LibraryPaths
    let lyricsCacheStore: LyricsCacheStore?
    let apiClient: APIClient?
    let fileManager: FileManager

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
        session: SyncPlaylistSession? = nil,
        includeLyrics: Bool = false,
        progress: (@Sendable @MainActor (_ current: Int, _ total: Int) -> Void)? = nil,
    ) async throws -> PreparedTransferBatch {
        #if os(tvOS)
            // tvOS is receiver-only; the sender flow is never invoked. This stub
            // keeps the symbol available without pulling SongExportItem and the
            // export metadata pipeline into the TV target.
            throw SyncTransferError.noPreparedSongs
        #else
            AppLog.info(
                self,
                "prepareBatch(tracks:) entry deviceName='\(sanitizedLogText(deviceName, maxLength: 60))' tracks=\(tracks.count) hasSession=\(session != nil) includeLyrics=\(includeLyrics)",
            )
            let items = tracks.map { track in
                SongExportItem(
                    sourceURL: paths.absoluteAudioURL(for: track.relativePath),
                    artistName: track.artistName,
                    title: track.title,
                    trackID: track.trackID,
                    albumID: track.albumID,
                    albumName: track.albumTitle.nilIfEmpty,
                    albumArtistName: track.albumArtistName,
                    trackNumber: track.trackNumber,
                    discNumber: track.discNumber,
                    genreName: track.genreName,
                    composerName: track.composerName,
                    releaseDate: track.releaseDate,
                )
            }
            return try await prepareBatch(
                deviceName: deviceName,
                items: items,
                session: session,
                includeLyrics: includeLyrics,
                progress: progress,
            )
        #endif
    }

    func cleanup(batch: PreparedTransferBatch?) {
        guard let batch else {
            return
        }
        cleanup(directoryURL: batch.cleanupDirectoryURL)
    }
}

nonisolated extension SyncPreparedTrackBuilder {
    struct PreparedFileNames {
        let audioFileName: String
        let lyricsFileName: String
    }

    struct PreparedTrack {
        let entry: SyncManifestEntry
        let fileURL: URL
        let companionURLs: [URL]
    }

    func makeCleanupDirectory() throws -> URL {
        let directoryURL = fileManager.temporaryDirectory
            .appendingPathComponent("am-transfer-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
        )
        return directoryURL
    }

    func sourceHasCatalogComment(at fileURL: URL, expectedTrackID: String) async -> Bool {
        do {
            let asset = AVURLAsset(url: fileURL)
            let items = try await AVMetadataHelper.collectMetadataItems(from: asset)
            var commentCount = 0
            var sawMismatchedTrackID: String?
            var sawInvalidAlbumID: String?
            var sawJSONFailure = false
            for item in items where item.identifier == .iTunesMetadataUserComment
                || AVMetadataHelper.matches(item, tokens: ["comment", "cmt"])
            {
                commentCount += 1
                guard let value = try? await item.load(.stringValue),
                      let data = value.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else {
                    sawJSONFailure = true
                    continue
                }
                guard let trackID = json["trackID"] as? String else {
                    sawJSONFailure = true
                    continue
                }
                guard trackID == expectedTrackID else {
                    sawMismatchedTrackID = trackID
                    continue
                }
                guard let albumID = json["albumID"] as? String, albumID.isCatalogID else {
                    sawInvalidAlbumID = json["albumID"] as? String ?? "nil"
                    continue
                }
                AppLog.verbose(
                    self,
                    "sourceHasCatalogComment match trackID=\(expectedTrackID) albumID=\(albumID) file=\(fileURL.lastPathComponent)",
                )
                return true
            }
            AppLog.verbose(
                self,
                "sourceHasCatalogComment no match trackID=\(expectedTrackID) totalMetadataItems=\(items.count) commentItems=\(commentCount) jsonFailure=\(sawJSONFailure) mismatchedTrackID=\(sawMismatchedTrackID ?? "nil") invalidAlbumID=\(sawInvalidAlbumID ?? "nil") file=\(fileURL.lastPathComponent)",
            )
        } catch {
            AppLog.verbose(self, "sourceHasCatalogComment check failed trackID=\(expectedTrackID) error=\(error.localizedDescription)")
        }
        return false
    }

    func copyExportSource(_ sourceURL: URL, to destinationURL: URL) throws {
        assert(!Thread.isMainThread)
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

    func cleanupPreparedFile(at fileURL: URL) {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return
        }
        do {
            try fileManager.removeItem(at: fileURL)
        } catch {
            AppLog.error(self, "cleanupPreparedFile failed path=\(fileURL.path) error=\(error.localizedDescription)")
        }
    }

    func cleanup(directoryURL: URL) {
        guard fileManager.fileExists(atPath: directoryURL.path) else {
            return
        }
        do {
            try fileManager.removeItem(at: directoryURL)
        } catch {
            AppLog.error(self, "cleanup failed path=\(directoryURL.path) error=\(error.localizedDescription)")
        }
    }

    func uniquePreparedFileNames(
        baseName: String,
        fileExtension: String,
        fallbackTrackID: String,
        usedFileNames: inout Set<String>,
    ) -> PreparedFileNames {
        let sanitizedBaseName = sanitizeDisplayFileName(baseName, fallback: fallbackTrackID)

        var candidateBaseName = sanitizedBaseName
        var audioFileName = "\(candidateBaseName).\(fileExtension)"
        var lyricsFileName = "\(candidateBaseName).lrc"
        var suffix = 2
        while usedFileNames.contains(audioFileName.lowercased())
            || usedFileNames.contains(lyricsFileName.lowercased())
        {
            candidateBaseName = "\(sanitizedBaseName) \(suffix)"
            audioFileName = "\(candidateBaseName).\(fileExtension)"
            lyricsFileName = "\(candidateBaseName).lrc"
            suffix += 1
        }
        usedFileNames.insert(audioFileName.lowercased())
        usedFileNames.insert(lyricsFileName.lowercased())
        return PreparedFileNames(
            audioFileName: audioFileName,
            lyricsFileName: lyricsFileName,
        )
    }

    static func preferredFileBaseName(
        artistName: String,
        title: String,
        fallbackBaseName: String,
    ) -> String {
        let artist = sanitizeDisplayFileName(artistName)
        let title = sanitizeDisplayFileName(title)

        if !artist.isEmpty, !title.isEmpty {
            return "\(artist) - \(title)"
        }
        if !title.isEmpty {
            return title
        }
        if !artist.isEmpty {
            return artist
        }

        return sanitizeDisplayFileName(fallbackBaseName, fallback: "Unknown")
    }
}
