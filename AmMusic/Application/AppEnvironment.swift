//
//  AppEnvironment.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import AmMusicDatabaseKit
import Combine
import Foundation
import Kingfisher
import UIKit

extension Notification.Name {
    static let libraryDidSync = Notification.Name("amusic.libraryDidSync")
    static let artworkDidUpdate = Notification.Name("amusic.artworkDidUpdate")
}

enum AppNotificationUserInfoKey {
    static let trackIDs = "trackIDs"
}

final class AppEnvironment {
    let paths: LibraryPaths
    let apiClient: APIClient
    let databaseManager: DatabaseManager
    let libraryDatabase: MusicLibraryDatabase
    let metadataReader: EmbeddedMetadataReader
    let lyricsCacheStore: LyricsCacheStore
    let libraryIndexer: SongLibraryIndexer
    let musicLibraryTrackRemovalService: MusicLibraryTrackRemovalService
    let networkMonitor: NetworkMonitor
    let playlistStore: PlaylistStore
    let downloadStore: DownloadStore
    let downloadManager: DownloadManager
    let playbackController: PlaybackController
    let lyricsService: LyricsService
    let audioFileImporter: AudioFileImporter
    let playlistCoverArtworkCache: PlaylistCoverArtworkCache

    var cancellables: Set<AnyCancellable> = []

    convenience init(
        apiBaseURL: URL = AppPreferences.defaultAPIBaseURL,
        baseDirectory: URL? = nil,
    ) {
        do {
            let manager = try Self.initializeDatabaseManagerSynchronously(
                apiBaseURL: apiBaseURL,
                baseDirectory: baseDirectory,
            )
            self.init(databaseManager: manager, apiBaseURL: apiBaseURL)
        } catch {
            AppLog.error("AppEnvironment", "DatabaseManager bootstrap failed: \(error)")
            fatalError("DatabaseManager bootstrap failed: \(error)")
        }
    }

    init(
        databaseManager: DatabaseManager,
        apiBaseURL: URL = AppPreferences.defaultAPIBaseURL,
    ) {
        let paths = databaseManager.paths
        self.paths = paths
        self.databaseManager = databaseManager
        apiClient = Self.makeAPIClient(apiBaseURL: apiBaseURL)
        Self.configureImageRequestAuthorization(apiClient: apiClient)

        metadataReader = EmbeddedMetadataReader()
        libraryDatabase = MusicLibraryDatabase(databaseManager: databaseManager, paths: paths)
        lyricsCacheStore = databaseManager.lyricsCacheStore
        libraryIndexer = SongLibraryIndexer(databaseManager: databaseManager)
        playlistStore = PlaylistStore(
            database: libraryDatabase,
            legacyFileURL: paths.legacyPlaylistURL,
        )
        downloadStore = DownloadStore(database: libraryDatabase, paths: paths)
        musicLibraryTrackRemovalService = MusicLibraryTrackRemovalService(
            databaseManager: databaseManager,
        )
        networkMonitor = NetworkMonitor()
        downloadManager = DownloadManager(
            paths: paths,
            databaseManager: databaseManager,
            downloadStore: downloadStore,
            apiClient: apiClient,
            lyricsCacheStore: databaseManager.lyricsCacheStore,
            networkMonitor: networkMonitor,
            screenAwakeHandler: { shouldKeepAwake in
                UIApplication.shared.isIdleTimerDisabled = shouldKeepAwake
            },
        )
        playbackController = PlaybackController(
            apiClient: apiClient,
            database: libraryDatabase,
            downloadStore: downloadStore,
            metadataReader: metadataReader,
            paths: paths,
            playlistStore: playlistStore,
        )
        lyricsService = LyricsService(
            apiClient: apiClient,
            lyricsCacheStore: databaseManager.lyricsCacheStore,
            database: libraryDatabase,
        )
        playlistCoverArtworkCache = PlaylistCoverArtworkCache()
        audioFileImporter = AudioFileImporter(
            paths: paths,
            database: libraryDatabase,
            metadataReader: metadataReader,
            apiClient: apiClient,
        )

        observeDatabaseEvents()
    }

    func resyncSongLibrary() async throws {
        _ = try await libraryIndexer.syncLibrary()
    }

    func rebuildLibraryDatabase(
        forceArtwork: Bool = false,
        progressCallback: (@Sendable (Int, Int) -> Void)? = nil,
    ) async throws -> SongLibraryIndexer.SyncResult {
        try await libraryIndexer.syncLibrary(
            forceArtwork: forceArtwork,
            progressCallback: progressCallback,
        )
    }

    func deleteAllStoredSongs() async throws {
        AppLog.warning(self, "deleteAllStoredSongs() entered")
        try await libraryDatabase.removeAllStoredSongs()
    }

    func librarySummary() -> MusicLibrarySummary {
        do {
            return try libraryDatabase.storedLibrarySummary()
        } catch {
            AppLog.warning(
                self,
                "libraryDatabase.storedLibrarySummary() threw - returning empty summary",
            )
            return MusicLibrarySummary(trackCount: 0, totalBytes: 0)
        }
    }
}
