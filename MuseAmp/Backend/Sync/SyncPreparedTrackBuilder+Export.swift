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
                    AppLog.warning(
                        self,
                        "prepareBatch skipped trackID=\(item.trackID) title='\(sanitizedLogText(item.title, maxLength: 80))' error=\(error.localizedDescription)",
                    )
                    skippedItems.append(PreparedTransferSkippedItem(
                        trackID: item.trackID,
                        title: item.title,
                        artistName: item.artistName,
                        reason: error.localizedDescription,
                    ))
                }
            }

            guard !entries.isEmpty else {
                cleanup(directoryURL: cleanupDirectoryURL)
                throw SyncTransferError.noPreparedSongs
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
            var exportInfo = ExportMetadataProcessor.ExportInfo(
                trackID: item.trackID,
                albumID: item.albumID,
                artworkURL: item.artworkURL,
                lyrics: lyrics,
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
                AppLog.verbose(
                    self,
                    "prepareItemWithMetadata artwork fetch trackID=\(item.trackID) bytes=\(exportInfo.artworkData?.count ?? 0)",
                )
            }

            do {
                try await ExportMetadataProcessor.embedExportMetadata(exportInfo, into: destinationURL)
                AppLog.info(self, "prepareItemWithMetadata embed succeeded trackID=\(item.trackID)")
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
            if metadataPresent {
                AppLog.info(self, "prepareItemWithMetadata skipped embed (metadata present) trackID=\(item.trackID)")
            } else {
                AppLog.info(
                    self,
                    "prepareItemWithMetadata embedding metadata trackID=\(item.trackID) albumID=\(item.albumID ?? "nil") hasArtworkURL=\(item.artworkURL != nil) title='\(sanitizedLogText(item.title, maxLength: 40))' artist='\(sanitizedLogText(item.artistName, maxLength: 40))'",
                )
                let normalizedLyrics = lyricsCacheStore?
                    .lyrics(for: item.trackID)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .nilIfEmpty
                var exportInfo = ExportMetadataProcessor.ExportInfo(
                    trackID: item.trackID,
                    albumID: item.albumID,
                    artworkURL: item.artworkURL,
                    lyrics: normalizedLyrics,
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
                    AppLog.verbose(
                        self,
                        "prepareItemWithMetadata artwork fetch trackID=\(item.trackID) bytes=\(exportInfo.artworkData?.count ?? 0)",
                    )
                }

                do {
                    try await ExportMetadataProcessor.embedExportMetadata(exportInfo, into: destinationURL)
                    AppLog.info(self, "prepareItemWithMetadata embed succeeded trackID=\(item.trackID)")
                } catch {
                    AppLog.error(
                        self,
                        "prepareItemWithMetadata embed failed trackID=\(item.trackID) error=\(error.localizedDescription)",
                    )
                    cleanupPreparedFile(at: destinationURL)
                    throw error
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
