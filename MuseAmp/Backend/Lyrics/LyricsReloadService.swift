//
//  LyricsReloadService.swift
//  MuseAmp
//
//  Created by @Lakr233 on 2026/04/13.
//

@preconcurrency import AVFoundation
import Foundation
import MuseAmpDatabaseKit

final class LyricsReloadService {
    nonisolated struct RebuildAllLyricsIndexResult: Sendable, Equatable {
        let tracksProcessed: Int
        let tracksSucceeded: Int
        let tracksFailed: Int
    }

    private let apiClient: APIClient
    private let lyricsCacheStore: LyricsCacheStore
    private let database: MusicLibraryDatabase
    private let paths: LibraryPaths

    init(
        apiClient: APIClient,
        lyricsCacheStore: LyricsCacheStore,
        database: MusicLibraryDatabase,
        paths: LibraryPaths,
    ) {
        self.apiClient = apiClient
        self.lyricsCacheStore = lyricsCacheStore
        self.database = database
        self.paths = paths
    }

    /// Reloads lyrics for a track: prefers offloading from the downloaded file, falling back to the
    /// remote server. When fetched from the server and the track is downloaded, the new lyrics are
    /// re-embedded into the file on disk. Always persists to the on-disk cache and posts
    /// `.lyricsDidUpdate` on success.
    ///
    /// A failed or empty server reply never discards lyrics the track already has: the cached
    /// lyrics stay, or the file's embedded lyrics are cached. A failed fetch still throws so the
    /// caller can report it; an empty reply returns the kept lyrics.
    @discardableResult
    func reloadLyrics(for trackID: String, forceRemoteFetch: Bool = false) async throws -> String {
        let track = database.trackOrNil(byID: trackID)
        let fileURL = track.map { paths.absoluteAudioURL(for: $0.relativePath) }

        if !forceRemoteFetch,
           let fileURL,
           let embedded = await EmbeddedLyricsReader.lyrics(fromFileAt: fileURL)
        {
            try lyricsCacheStore.saveLyrics(embedded, for: trackID)
            postLyricsDidUpdate(trackID: trackID)
            AppLog.info(
                self,
                "reloadLyrics source=embedded trackID=\(trackID) length=\(embedded.count)",
            )
            return embedded
        }

        AppLog.info(self, "reloadLyrics source=network-start trackID=\(trackID)")
        let fetched: String
        do {
            fetched = try await apiClient.lyrics(id: trackID, bypassCache: true)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            _ = await keepLocalLyrics(for: trackID, fileURL: fileURL)
            throw error
        }

        guard !fetched.isEmpty else {
            if let kept = await keepLocalLyrics(for: trackID, fileURL: fileURL) {
                AppLog.info(
                    self,
                    "reloadLyrics source=network-empty kept local lyrics trackID=\(trackID) length=\(kept.count)",
                )
                return kept
            }
            try lyricsCacheStore.saveLyrics(fetched, for: trackID)
            postLyricsDidUpdate(trackID: trackID)
            AppLog.info(self, "reloadLyrics source=network-empty trackID=\(trackID)")
            return fetched
        }

        try lyricsCacheStore.saveLyrics(fetched, for: trackID)

        if let fileURL, let track, FileManager.default.isReadableFile(atPath: fileURL.path) {
            await embedLyricsIfPossible(fetched, into: fileURL, track: track)
        }

        postLyricsDidUpdate(trackID: trackID)
        AppLog.info(
            self,
            "reloadLyrics source=network-success trackID=\(trackID) length=\(fetched.count)",
        )
        return fetched
    }

    /// Re-fetches lyrics for every track. Tracks whose fetch fails keep their current lyrics
    /// (see `reloadLyrics`); cache entries for tracks no longer in the library are removed.
    func rebuildAllLyricsIndex(
        progressCallback: (@Sendable (_ current: Int, _ total: Int, _ trackTitle: String) -> Void)? = nil,
    ) async throws -> RebuildAllLyricsIndexResult {
        let tracks = try database.allTracks()
            .sorted { lhs, rhs in
                let lhsArtist = lhs.artistName.localizedCaseInsensitiveCompare(rhs.artistName)
                if lhsArtist != .orderedSame {
                    return lhsArtist == .orderedAscending
                }
                let lhsAlbum = lhs.albumTitle.localizedCaseInsensitiveCompare(rhs.albumTitle)
                if lhsAlbum != .orderedSame {
                    return lhsAlbum == .orderedAscending
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }

        AppLog.info(self, "rebuildAllLyricsIndex started total=\(tracks.count)")
        removeOrphanedLyrics(keeping: tracks.map(\.trackID))

        var tracksSucceeded = 0
        var tracksFailed = 0

        for (index, track) in tracks.enumerated() {
            progressCallback?(index, tracks.count, track.title)
            do {
                _ = try await reloadLyrics(for: track.trackID, forceRemoteFetch: true)
                tracksSucceeded += 1
            } catch {
                tracksFailed += 1
                AppLog.error(
                    self,
                    "rebuildAllLyricsIndex track failed trackID=\(track.trackID) error=\(error.localizedDescription)",
                )
            }
        }

        AppLog.info(
            self,
            "rebuildAllLyricsIndex completed total=\(tracks.count) success=\(tracksSucceeded) failed=\(tracksFailed)",
        )
        return RebuildAllLyricsIndexResult(
            tracksProcessed: tracks.count,
            tracksSucceeded: tracksSucceeded,
            tracksFailed: tracksFailed,
        )
    }

    /// Lyrics the track already has after a failed or empty fetch: its non-empty cached lyrics,
    /// or else its embedded lyrics, which are cached so the lyric page and search find them.
    private func keepLocalLyrics(for trackID: String, fileURL: URL?) async -> String? {
        if let cached = lyricsCacheStore.lyrics(for: trackID),
           !cached.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return cached
        }
        guard let fileURL, let embedded = await EmbeddedLyricsReader.lyrics(fromFileAt: fileURL) else {
            return nil
        }
        do {
            try lyricsCacheStore.saveLyrics(embedded, for: trackID)
        } catch {
            AppLog.error(self, "keepLocalLyrics cache write failed trackID=\(trackID) error=\(error.localizedDescription)")
            return nil
        }
        postLyricsDidUpdate(trackID: trackID)
        AppLog.info(self, "keepLocalLyrics source=embedded trackID=\(trackID) length=\(embedded.count)")
        return embedded
    }

    private func removeOrphanedLyrics(keeping trackIDs: [String]) {
        let directory = paths.lyricsCacheDirectory
        let keptFileNames = Set(trackIDs.map { paths.lyricsCacheURL(for: $0).lastPathComponent })
        let fileNames: [String]
        do {
            fileNames = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        } catch {
            AppLog.warning(self, "removeOrphanedLyrics listing failed error=\(error.localizedDescription)")
            return
        }
        for fileName in fileNames where !keptFileNames.contains(fileName) {
            do {
                try FileManager.default.removeItem(at: directory.appendingPathComponent(fileName))
            } catch {
                AppLog.error(self, "removeOrphanedLyrics remove failed file=\(fileName) error=\(error.localizedDescription)")
            }
        }
    }

    private func embedLyricsIfPossible(
        _ lyrics: String,
        into fileURL: URL,
        track: AudioTrackRecord,
    ) async {
        let info = ExportMetadataProcessor.ExportInfo(
            trackID: track.trackID,
            albumID: track.albumID,
            artworkURL: nil,
            artworkData: nil,
            lyrics: lyrics,
            title: track.title,
            artistName: track.artistName,
            albumName: track.albumTitle,
        )
        do {
            try ExportMetadataProcessor.validateExportInfo(info)
            try await ExportMetadataProcessor.embedExportMetadata(info, into: fileURL)
        } catch {
            AppLog.warning(
                self,
                "reloadLyrics re-embed failed trackID=\(track.trackID) error=\(error.localizedDescription)",
            )
        }
    }

    private func postLyricsDidUpdate(trackID: String) {
        NotificationCenter.default.post(
            name: .lyricsDidUpdate,
            object: nil,
            userInfo: [AppNotificationUserInfoKey.trackIDs: [trackID]],
        )
    }
}
