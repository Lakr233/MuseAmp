import AmMusicDatabaseKit
import Foundation

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
