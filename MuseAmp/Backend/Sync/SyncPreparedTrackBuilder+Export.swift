//
//  SyncPreparedTrackBuilder+Export.swift
//  MuseAmp
//
//  Created by @Lakr233 on 2026/04/11.
//

@preconcurrency import AVFoundation
import Foundation
import MuseAmpDatabaseKit

nonisolated extension SyncPreparedTrackBuilder {
    func prepareBatch(
        deviceName: String,
        items: [SongExportItem],
        session: SyncPlaylistSession? = nil,
        includeLyrics: Bool = false,
        progress: (@Sendable @MainActor (_ current: Int, _ total: Int) -> Void)? = nil,
    ) async throws -> PreparedTransferBatch {
        guard !items.isEmpty else {
            throw SyncTransferError.noPreparedSongs
        }

        let detachedTask = Task.detached(priority: .userInitiated) { [self] () -> PreparedTransferBatch in
            assert(!Thread.isMainThread)
            let cleanupDirectoryURL = try makeCleanupDirectory()
            var entries: [SyncManifestEntry] = []
            var filesByTrackID: [String: URL] = [:]
            var companionFilesByTrackID: [String: [URL]] = [:]
            var skippedItems: [PreparedTransferSkippedItem] = []
            var usedFileNames = Set<String>()

            do {
                for (index, item) in items.enumerated() {
                    try Task.checkCancellation()
                    await progress?(index + 1, items.count)

                    do {
                        let prepared = try await prepareItemWithMetadata(
                            item,
                            cleanupDirectoryURL: cleanupDirectoryURL,
                            usedFileNames: &usedFileNames,
                            includeLyrics: includeLyrics,
                        )
                        entries.append(prepared.entry)
                        filesByTrackID[prepared.entry.trackID] = prepared.fileURL
                        companionFilesByTrackID[prepared.entry.trackID] = prepared.companionURLs
                    } catch {
                        try Task.checkCancellation()
                        let isSourceUnreadable = await sourceIsUnreadable(at: item.sourceURL)
                        AppLog.warning(
                            self,
                            "prepareBatch skipped trackID=\(item.trackID) title='\(sanitizedLogText(item.title, maxLength: 80))' sourceUnreadable=\(isSourceUnreadable) error=\(error.localizedDescription)",
                        )
                        skippedItems.append(PreparedTransferSkippedItem(
                            trackID: item.trackID,
                            title: item.title,
                            artistName: item.artistName,
                            reason: error.localizedDescription,
                            isSourceUnreadable: isSourceUnreadable,
                        ))
                    }
                }
                // A cancel during the last song must not hand back a batch.
                try Task.checkCancellation()

                guard !entries.isEmpty else {
                    throw SyncTransferError.noPreparedSongs
                }
            } catch {
                AppLog.info(self, "prepareBatch abandoned prepared=\(entries.count)/\(items.count) error=\(error.localizedDescription)")
                cleanup(directoryURL: cleanupDirectoryURL)
                throw error
            }

            var effectiveSession = session
            if let session, !skippedItems.isEmpty {
                let preparedTrackIDs = Set(entries.map(\.trackID))
                effectiveSession = SyncPlaylistSession(
                    playlistName: session.playlistName,
                    sessionID: session.sessionID,
                    orderedTrackIDs: session.orderedTrackIDs.filter { preparedTrackIDs.contains($0) },
                    createdAt: session.createdAt,
                )
                AppLog.info(
                    self,
                    "prepareBatch filtered session tracks \(session.orderedTrackIDs.count) -> \(effectiveSession?.orderedTrackIDs.count ?? 0) after skips",
                )
            }
            let manifest = SyncManifest(
                deviceName: deviceName,
                session: effectiveSession,
                entries: entries,
            )
            AppLog.info(self, "prepareBatch prepared \(entries.count)/\(items.count) track(s) skipped=\(skippedItems.count)")
            return PreparedTransferBatch(
                manifest: manifest,
                filesByTrackID: filesByTrackID,
                companionFilesByTrackID: companionFilesByTrackID,
                cleanupDirectoryURL: cleanupDirectoryURL,
                skippedItems: skippedItems,
            )
        }

        return try await withTaskCancellationHandler {
            try await detachedTask.value
        } onCancel: {
            detachedTask.cancel()
        }
    }

    func prepareItemWithMetadata(
        _ item: SongExportItem,
        cleanupDirectoryURL: URL,
        usedFileNames: inout Set<String>,
        includeLyrics: Bool = false,
    ) async throws -> PreparedTrack {
        assert(!Thread.isMainThread)
        let fileNames = uniquePreparedFileNames(
            baseName: item.preferredFileBaseName,
            fileExtension: item.sourceURL.pathExtension.nilIfEmpty ?? "m4a",
            fallbackTrackID: item.trackID,
            usedFileNames: &usedFileNames,
        )
        let destinationURL = cleanupDirectoryURL.appendingPathComponent(fileNames.audioFileName)

        try copyExportSource(item.sourceURL, to: destinationURL)

        if includeLyrics {
            AppLog.info(
                self,
                "prepareItemWithMetadata embedding metadata+lyrics trackID=\(item.trackID) albumID=\(item.albumID ?? "nil") hasArtworkURL=\(item.artworkURL != nil) title='\(sanitizedLogText(item.title, maxLength: 40))' artist='\(sanitizedLogText(item.artistName, maxLength: 40))'",
            )
            let lyrics = await fetchOrCachedLyrics(for: item.trackID)
            do {
                try await embedMetadata(for: item, lyrics: lyrics, into: destinationURL)
            } catch {
                AppLog.error(
                    self,
                    "prepareItemWithMetadata embed failed trackID=\(item.trackID) error=\(error.localizedDescription)",
                )
                cleanupPreparedFile(at: destinationURL)
                throw error
            }
        } else {
            let metadataPresent = await sourceHasCatalogComment(
                at: item.sourceURL,
                expectedTrackID: item.trackID,
            )
            // The receiver only imports lyrics embedded in the file, so lyrics
            // fetched or edited after the download must be embedded again.
            let cachedLyrics = lyricsCacheStore?
                .lyrics(for: item.trackID)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty
            let embeddedLyrics = await sourceEmbeddedLyrics(at: item.sourceURL)
            var cachedLyricsDiffer = false
            if let cachedLyrics {
                cachedLyricsDiffer = Self.lyricsComparisonKey(cachedLyrics)
                    != embeddedLyrics.map(Self.lyricsComparisonKey)
            }
            if metadataPresent, !cachedLyricsDiffer {
                AppLog.info(self, "prepareItemWithMetadata skipped embed (metadata present) trackID=\(item.trackID)")
            } else {
                AppLog.info(
                    self,
                    "prepareItemWithMetadata embedding metadata trackID=\(item.trackID) albumID=\(item.albumID ?? "nil") metadataPresent=\(metadataPresent) cachedLyricsDiffer=\(cachedLyricsDiffer) hasArtworkURL=\(item.artworkURL != nil) title='\(sanitizedLogText(item.title, maxLength: 40))' artist='\(sanitizedLogText(item.artistName, maxLength: 40))'",
                )
                // A re-embed rewrites the catalog comment, so carry over the
                // artwork URL the download wrote; the receiver repairs
                // missing artwork from it.
                let preservedArtworkURL = metadataPresent && item.artworkURL == nil
                    ? await sourceCommentArtworkURL(at: item.sourceURL)
                    : nil
                do {
                    try await embedMetadata(
                        for: item,
                        lyrics: cachedLyrics ?? embeddedLyrics,
                        preservedArtworkURL: preservedArtworkURL,
                        into: destinationURL,
                    )
                } catch {
                    try Task.checkCancellation()
                    guard metadataPresent else {
                        AppLog.error(
                            self,
                            "prepareItemWithMetadata embed failed trackID=\(item.trackID) error=\(error.localizedDescription)",
                        )
                        cleanupPreparedFile(at: destinationURL)
                        throw error
                    }
                    // The untouched copy still carries its catalog comment, so
                    // it imports fine; only the lyrics update is lost.
                    AppLog.warning(
                        self,
                        "prepareItemWithMetadata lyrics update failed, sending file as-is trackID=\(item.trackID) error=\(error.localizedDescription)",
                    )
                }
            }
        }

        let asset = AVURLAsset(url: destinationURL)
        let duration = try await asset.load(.duration)
        let entry = SyncManifestEntry(
            trackID: item.trackID,
            albumID: item.albumID,
            title: item.title,
            artistName: item.artistName,
            albumTitle: item.albumName ?? String(localized: "Unknown Album"),
            durationSeconds: max(duration.seconds, 0),
            fileExtension: destinationURL.pathExtension.lowercased(),
        )
        return PreparedTrack(
            entry: entry,
            fileURL: destinationURL,
            companionURLs: [],
        )
    }

    /// `preservedArtworkURL` only goes into the catalog comment; artwork is
    /// fetched for `item.artworkURL` alone.
    func embedMetadata(
        for item: SongExportItem,
        lyrics: String?,
        preservedArtworkURL: URL? = nil,
        into destinationURL: URL,
    ) async throws {
        var exportInfo = ExportMetadataProcessor.ExportInfo(
            trackID: item.trackID,
            albumID: item.albumID,
            artworkURL: item.artworkURL ?? preservedArtworkURL,
            lyrics: lyrics,
            title: item.title,
            artistName: item.artistName,
            albumName: item.albumName,
        )
        try ExportMetadataProcessor.validateExportInfo(exportInfo)

        if exportInfo.artworkData == nil,
           let artworkURL = item.artworkURL
        {
            do {
                exportInfo.artworkData = try await DownloadArtworkProcessor.cachedArtworkData(
                    trackID: item.trackID,
                    artworkURL: artworkURL,
                    apiClient: apiClient,
                    locations: paths,
                    session: .shared,
                )
            } catch {
                AppLog.warning(
                    self,
                    "prepareItemWithMetadata artwork fetch failed trackID=\(item.trackID) error=\(error.localizedDescription)",
                )
            }
            AppLog.verbose(
                self,
                "prepareItemWithMetadata artwork fetch trackID=\(item.trackID) bytes=\(exportInfo.artworkData?.count ?? 0)",
            )
        }

        do {
            try await ExportMetadataProcessor.embedExportMetadata(exportInfo, into: destinationURL)
        } catch DownloadArtworkProcessor.ProcessingError.exportTimedOut {
            // A busy or briefly suspended device can outlast the timeout on a
            // healthy file, so give the export one more try.
            try Task.checkCancellation()
            AppLog.warning(self, "prepareItemWithMetadata embed timed out, retrying trackID=\(item.trackID)")
            try await ExportMetadataProcessor.embedExportMetadata(exportInfo, into: destinationURL)
        }
        AppLog.info(self, "prepareItemWithMetadata embed succeeded trackID=\(item.trackID)")
    }

    func sourceEmbeddedLyrics(at fileURL: URL) async -> String? {
        do {
            let items = try await AVMetadataHelper.collectMetadataItems(from: AVURLAsset(url: fileURL))
            return await EmbeddedMetadataReader().extractLyrics(from: items)
        } catch {
            AppLog.verbose(self, "sourceEmbeddedLyrics read failed file=\(fileURL.lastPathComponent) error=\(error.localizedDescription)")
            return nil
        }
    }

    func sourceCommentArtworkURL(at fileURL: URL) async -> URL? {
        do {
            let items = try await AVMetadataHelper.collectMetadataItems(from: AVURLAsset(url: fileURL))
            for item in items where item.identifier == .iTunesMetadataUserComment
                || AVMetadataHelper.matches(item, tokens: ["comment", "cmt"])
            {
                guard let comment = try await item.load(.stringValue),
                      let artworkURL = TrackArtworkRepairService.embeddedArtworkURL(fromComment: comment)
                else {
                    continue
                }
                return artworkURL
            }
        } catch {
            AppLog.warning(self, "sourceCommentArtworkURL read failed file=\(fileURL.lastPathComponent) error=\(error.localizedDescription)")
        }
        return nil
    }

    /// Whether a song that failed to prepare failed because its file cannot
    /// be read or played. Only those are reported as unreadable and offered
    /// for removal; a healthy file that hit a timeout or a file-name limit is
    /// not.
    func sourceIsUnreadable(at fileURL: URL) async -> Bool {
        guard fileManager.isReadableFile(atPath: fileURL.path) else {
            return true
        }
        do {
            let (isReadable, isPlayable) = try await AVURLAsset(url: fileURL).load(.isReadable, .isPlayable)
            return !(isReadable && isPlayable)
        } catch {
            AppLog.warning(self, "sourceIsUnreadable load failed file=\(fileURL.lastPathComponent) error=\(error.localizedDescription)")
            return true
        }
    }

    static func lyricsComparisonKey(_ lyrics: String) -> String {
        lyrics
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func fetchOrCachedLyrics(for trackID: String) async -> String? {
        if let cached = lyricsCacheStore?
            .lyrics(for: trackID)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        {
            return cached
        }
        guard let apiClient else { return nil }
        do {
            let fetched = try await apiClient.lyrics(id: trackID)
            let normalized = fetched.trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalized.isEmpty {
                try? lyricsCacheStore?.saveLyrics(normalized, for: trackID)
                AppLog.verbose(self, "fetchOrCachedLyrics fetched trackID=\(trackID) length=\(normalized.count)")
            }
            return normalized.nilIfEmpty
        } catch {
            AppLog.verbose(self, "fetchOrCachedLyrics fetch failed trackID=\(trackID) error=\(error.localizedDescription)")
            return nil
        }
    }
}
