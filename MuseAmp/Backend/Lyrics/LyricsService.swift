//
//  LyricsService.swift
//  MuseAmp
//
//  Created by @Lakr233 on 2026/04/11.
//

import Foundation
import MuseAmpDatabaseKit

final class LyricsService {
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
    func loadLyricsThrowing(for trackID: String) async throws -> String {
        if let cached = cachedLyrics(for: trackID) {
            return cached
        }
        let lyrics = try await fetchLyrics(for: trackID)
        persistLyricsIfDownloaded(lyrics, for: trackID)
        return lyrics
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
}
