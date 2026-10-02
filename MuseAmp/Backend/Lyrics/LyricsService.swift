//
//  LyricsService.swift
//  MuseAmp
//
//  Created by @Lakr233 on 2026/04/11.
//

import Foundation
import MuseAmpDatabaseKit
import SubsonicClientKit

final class LyricsService {
    /// Waits before each retry of a transient fetch failure.
    nonisolated static let retryDelays: [TimeInterval] = [2, 6]

    private let apiClient: APIClient
    private let lyricsCacheStore: LyricsCacheStore
    private let database: MusicLibraryDatabase

    init(apiClient: APIClient, lyricsCacheStore: LyricsCacheStore, database: MusicLibraryDatabase) {
        self.apiClient = apiClient
        self.lyricsCacheStore = lyricsCacheStore
        self.database = database
    }

    func cachedLyrics(for trackID: String) -> String? {
        lyricsCacheStore.lyrics(for: trackID)
    }

    func fetchLyrics(for trackID: String) async throws -> String {
        try await apiClient.lyrics(id: trackID)
    }

    /// Loads lyrics for a track: tries cache first, falls back to network fetch.
    /// Designed to be passed as the `lyricsLoader` closure to `LyricTimelineView.bindDataSource`.
    func loadLyrics(for trackID: String) async -> String? {
        do {
            return try await loadLyricsThrowing(for: trackID)
        } catch {
            AppLog.error(self, "loadLyrics failed trackID=\(trackID) error=\(error)")
            return nil
        }
    }

    /// Same as `loadLyrics(for:)` but surfaces fetch failures to the caller so a
    /// transient network error can be retried instead of rendering as "no lyrics".
    ///
    /// Order: cached lyrics, then the lyrics embedded in the downloaded file
    /// (cached on the way so later loads and lyric search find them), then the
    /// server. An empty cache entry records a server answer of "no lyrics" and
    /// is returned without asking the server again; a "not found" error reply
    /// counts as that answer too. A bare HTTP 404 shows as no lyrics but is
    /// not remembered, since it more often means the endpoint is unreachable
    /// than that the song has none. Without a configured server there is
    /// nowhere else to look, so the track has no lyrics.
    func loadLyricsThrowing(for trackID: String) async throws -> String {
        let cached = cachedLyrics(for: trackID)
        if let cached, !cached.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return cached
        }
        if let embedded = await embeddedLyrics(for: trackID) {
            AppLog.info(self, "loadLyrics source=embedded trackID=\(trackID) length=\(embedded.count)")
            persistLyricsIfDownloaded(embedded, for: trackID)
            return embedded
        }
        if let cached {
            return cached
        }
        guard apiClient.hasConfiguredServer else {
            AppLog.verbose(self, "loadLyrics no local lyrics and no server configured trackID=\(trackID)")
            return ""
        }
        let lyrics: String
        do {
            lyrics = try await fetchLyrics(for: trackID)
        } catch where Self.isNoLyricsAnswer(error) {
            AppLog.info(self, "loadLyrics server has no lyrics trackID=\(trackID) error=\(error)")
            lyrics = ""
        } catch where Self.isEndpointNotFound(error) {
            AppLog.warning(self, "loadLyrics lyrics endpoint not found, showing none without remembering trackID=\(trackID) error=\(error)")
            return ""
        }
        persistLyricsIfDownloaded(lyrics, for: trackID)
        return lyrics
    }

    /// `loadLyricsThrowing(for:)` with a backoff retry for failures that may
    /// clear up on their own (unreachable server, 5xx). Permanent failures,
    /// such as an error reply from the server, throw at once.
    func loadLyricsRetrying(for trackID: String) async throws -> String {
        var attempt = 0
        while true {
            do {
                return try await loadLyricsThrowing(for: trackID)
            } catch {
                guard attempt < Self.retryDelays.count, Self.isTransientFetchError(error) else {
                    throw error
                }
                let delay = Self.retryDelays[attempt]
                attempt += 1
                AppLog.warning(self, "loadLyrics retrying trackID=\(trackID) attempt=\(attempt) delay=\(delay)s error=\(error)")
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }

    nonisolated static func isTransientFetchError(_ error: any Error) -> Bool {
        switch error {
        case APIError.transportFailed:
            true
        case let APIError.requestFailed(statusCode, _):
            statusCode == 408 || statusCode == 429 || (500 ... 599).contains(statusCode)
        default:
            false
        }
    }

    /// The server's confirmed answer that it has no lyrics for the song,
    /// safe to remember: Subsonic error 70 ("data not found"), or a generic
    /// error reply that wraps an upstream 404 (wrapper-rs: "apple api request
    /// failed: 404 Not Found"). Other Subsonic codes (authentication,
    /// permission, version) are real failures whatever their message says.
    nonisolated static func isNoLyricsAnswer(_ error: any Error) -> Bool {
        guard case let APIError.subsonicRequestFailed(code, message) = error else {
            return false
        }
        if code == 70 {
            return true
        }
        guard code == nil || code == 0 else {
            return false
        }
        let text = message.lowercased()
        return text.contains("404") || text.contains("not found")
    }

    /// A bare HTTP 404: a server without a lyrics endpoint, a wrong base path,
    /// or a proxy during maintenance. Not an answer about this song.
    nonisolated static func isEndpointNotFound(_ error: any Error) -> Bool {
        guard case let APIError.requestFailed(statusCode, _) = error else {
            return false
        }
        return statusCode == 404
    }

    func persistLyricsIfDownloaded(_ lyrics: String, for trackID: String) {
        guard database.hasTrack(byID: trackID) else {
            return
        }
        do {
            try lyricsCacheStore.saveLyrics(lyrics, for: trackID)
        } catch {
            AppLog.error(self, "persistLyricsIfDownloaded failed trackID=\(trackID) error=\(error)")
        }
    }

    private func embeddedLyrics(for trackID: String) async -> String? {
        guard let track = database.trackOrNil(byID: trackID) else {
            return nil
        }
        return await EmbeddedLyricsReader.lyrics(fromFileAt: database.paths.absoluteAudioURL(for: track.relativePath))
    }
}
