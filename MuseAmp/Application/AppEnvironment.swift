//
//  AppEnvironment.swift
//  MuseAmp
//
//  Created by @Lakr233 on 2026/04/11.
//

import Combine
import Foundation
import Kingfisher
import MuseAmpDatabaseKit
import UIKit

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
    let lyricsReloadService: LyricsReloadService
    let audioFileImporter: AudioFileImporter
    let playlistCoverArtworkCache: PlaylistCoverArtworkCache
    let trackArtworkRepairService: TrackArtworkRepairService
    let screenAwakeCoordinator: ScreenAwakeCoordinator

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
        apiClient = APIClient(baseURL: apiBaseURL)
        Self.configureImagePipeline()

        metadataReader = EmbeddedMetadataReader()
        libraryDatabase = MusicLibraryDatabase(databaseManager: databaseManager, paths: paths)
        lyricsCacheStore = databaseManager.lyricsCacheStore
        libraryIndexer = SongLibraryIndexer(databaseManager: databaseManager)
        playlistStore = PlaylistStore(database: libraryDatabase)
        downloadStore = DownloadStore(database: libraryDatabase, paths: paths)
        musicLibraryTrackRemovalService = MusicLibraryTrackRemovalService(
            databaseManager: databaseManager,
        )
        networkMonitor = NetworkMonitor()
        let screenAwakeCoordinator = ScreenAwakeCoordinator()
        self.screenAwakeCoordinator = screenAwakeCoordinator
        downloadManager = DownloadManager(
            paths: paths,
            databaseManager: databaseManager,
            downloadStore: downloadStore,
            apiClient: apiClient,
            lyricsCacheStore: databaseManager.lyricsCacheStore,
            networkMonitor: networkMonitor,
            screenAwakeHandler: { shouldKeepAwake in
                screenAwakeCoordinator.setActive(shouldKeepAwake, for: .downloadsActive)
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
        lyricsReloadService = LyricsReloadService(
            apiClient: apiClient,
            lyricsCacheStore: databaseManager.lyricsCacheStore,
            database: libraryDatabase,
            paths: paths,
        )
        playlistCoverArtworkCache = PlaylistCoverArtworkCache()
        audioFileImporter = AudioFileImporter(
            paths: paths,
            database: libraryDatabase,
            metadataReader: metadataReader,
            apiClient: apiClient,
        )
        trackArtworkRepairService = TrackArtworkRepairService(
            paths: paths,
            apiClient: apiClient,
        )

        refreshTrackTitleSanitizer()
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

    func rebuildAllLyricsIndex(
        progressCallback: (@Sendable (_ current: Int, _ total: Int, _ trackTitle: String) -> Void)? = nil,
    ) async throws -> LyricsReloadService.RebuildAllLyricsIndexResult {
        try await lyricsReloadService.rebuildAllLyricsIndex(progressCallback: progressCallback)
    }

    func refreshTrackTitleSanitizer() {
        do {
            try TrackTitleSanitizer.refresh(titles: libraryDatabase.allTracks().map(\.title))
        } catch {
            AppLog.error(self, "refreshTrackTitleSanitizer failed error=\(error)")
        }
    }
}
