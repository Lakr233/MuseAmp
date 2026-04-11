//
//  DownloadLyricsProcessor.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import AmMusicDatabaseKit
import Foundation

enum DownloadLyricsProcessor {
    private static let logger = "DownloadLyricsProcessor"

    static func cacheLyrics(
        trackID: String,
        apiClient: APIClient?,
        lyricsStore: LyricsCacheStore,
    ) async {
        guard let apiClient else {
            return
        }

        do {
            let lyrics = try await apiClient.lyrics(id: trackID)
            let normalizedLyrics = lyrics.trimmingCharacters(in: .whitespacesAndNewlines)
            try lyricsStore.saveLyrics(normalizedLyrics, for: trackID)
        } catch {
            AppLog.warning(logger, "cacheLyrics failed trackID=\(trackID) error=\(error.localizedDescription)")
        }
    }
}
