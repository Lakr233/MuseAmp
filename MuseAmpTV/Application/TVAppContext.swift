//
//  TVAppContext.swift
//  MuseAmpTV
//
//  Created by @Lakr233 on 2026/04/11.
//

import Foundation
import MuseAmpDatabaseKit

@MainActor
final class TVAppContext {
    struct PendingSessionAlert: Equatable {
        let title: String
        let message: String
    }

    let paths: LibraryPaths
    let libraryDatabase: MusicLibraryDatabase
    let playbackController: PlaybackController
    let lyricsService: LyricsService
    let syncTransferSession: SyncTransferSession
    let playlistSessionStore: TVPlaylistSessionStore

    var currentSessionManifest: TVPlaylistSessionManifest?
    private var pendingSessionAlert: PendingSessionAlert?
    private var lastUserInteractionDate: Date = .distantPast
    var isWithinUserInteractionWindow: Bool {
        Date().timeIntervalSince(lastUserInteractionDate) < 5.0
    }

    func recordUserInteraction() {
        lastUserInteractionDate = Date()
    }

    convenience init(
        apiBaseURL: URL = AppPreferences.defaultAPIBaseURL,
        baseDirectory: URL? = nil,
    ) {
        do {
            let manager = try Self.initializeDatabaseManager(
                apiBaseURL: apiBaseURL,
                baseDirectory: baseDirectory,
            )
            self.init(
                databaseManager: manager,
                apiBaseURL: apiBaseURL,
            )
        } catch {
            AppLog.error("TVAppContext", "DatabaseManager bootstrap failed: \(error)")
            fatalError("DatabaseManager bootstrap failed: \(error)")
        }
    }

    init(
        databaseManager: DatabaseManager,
        apiBaseURL: URL = AppPreferences.defaultAPIBaseURL,
    ) {
        let paths = databaseManager.paths
        self.paths = paths
        let apiClient = APIClient(baseURL: apiBaseURL)
        Self.configureImagePipeline()

        let metadataReader = EmbeddedMetadataReader()
        let libraryDatabase = MusicLibraryDatabase(databaseManager: databaseManager, paths: paths)
        self.libraryDatabase = libraryDatabase
        let lyricsCacheStore = databaseManager.lyricsCacheStore
        let playlistStore = PlaylistStore(database: libraryDatabase)
        let downloadStore = DownloadStore(database: libraryDatabase, paths: paths)
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
            lyricsCacheStore: lyricsCacheStore,
            database: libraryDatabase,
        )
        let audioFileImporter = AudioFileImporter(
            paths: paths,
            database: libraryDatabase,
            metadataReader: metadataReader,
            apiClient: apiClient,
        )
        syncTransferSession = SyncTransferSession(
            paths: paths,
            libraryDatabase: libraryDatabase,
            lyricsCacheStore: lyricsCacheStore,
            audioFileImporter: audioFileImporter,
            apiClient: apiClient,
        )
        playlistSessionStore = Self.makePlaylistSessionStore(paths: paths)
        refreshTrackTitleSanitizer()
    }

    func allTracks() -> [AudioTrackRecord] {
        do {
            return try libraryDatabase.allTracks()
        } catch {
            AppLog.error(self, "allTracks failed: \(error)")
            return []
        }
    }

    func clearSessionLibrary() async {
        playbackController.stop()
        playbackController.persistPlaybackState()
        await syncTransferSession.stopAll()
        do {
            try await libraryDatabase.removeAllStoredSongs()
        } catch {
            AppLog.error(self, "clearSessionLibrary failed: \(error)")
        }
        playlistSessionStore.clear()
        currentSessionManifest = nil
    }

    func takePendingSessionAlert() -> PendingSessionAlert? {
        guard let pendingSessionAlert else {
            return nil
        }
        let trimmedMessage = pendingSessionAlert.message.trimmingCharacters(in: .whitespacesAndNewlines)
        self.pendingSessionAlert = nil
        guard !trimmedMessage.isEmpty else {
            return nil
        }
        return PendingSessionAlert(
            title: pendingSessionAlert.title,
            message: trimmedMessage,
        )
    }

    func takePendingSessionAlertMessage() -> String? {
        takePendingSessionAlert()?.message
    }

    func setPendingSessionAlert(
        title: String,
        message: String,
    ) {
        pendingSessionAlert = PendingSessionAlert(title: title, message: message)
    }

    func refreshTrackTitleSanitizer() {
        do {
            try TrackTitleSanitizer.refresh(titles: libraryDatabase.allTracks().map(\.title))
        } catch {
            AppLog.error(self, "refreshTrackTitleSanitizer failed: \(error)")
        }
    }
}
