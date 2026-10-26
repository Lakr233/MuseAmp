import Combine
import Foundation
@testable import MuseAmp
import MuseAmpDatabaseKit
import Testing

@Suite(.serialized)
struct DownloadStoreFacadeTests {
    private func makeStoreComponents() throws -> (
        TestLibrarySandbox,
        LibraryPaths,
        MusicLibraryDatabase,
        DownloadStore,
    ) {
        let sandbox = TestLibrarySandbox()
        let database = try sandbox.makeDatabase()
        let paths = database.paths
        let store = DownloadStore(database: database, paths: paths)
        return (sandbox, paths, database, store)
    }

    @MainActor
    private func makeManager(database: MusicLibraryDatabase, store: DownloadStore) -> DownloadManager {
        DownloadManager(
            paths: database.paths,
            databaseManager: database.databaseManager,
            downloadStore: store,
            apiClient: APIClient(baseURL: URL(string: "https://example.invalid")!),
            lyricsCacheStore: LyricsCacheStore(paths: database.paths),
            networkMonitor: NetworkMonitor(),
            screenAwakeHandler: { _ in },
        )
    }

    @Test
    @MainActor
    func `local track and album identities are skipped without creating download jobs`() throws {
        let (sandbox, _, database, store) = try makeStoreComponents()
        _ = sandbox
        let manager = makeManager(database: database, store: store)
        let localTrack = "local-track-" + String(repeating: "a", count: 64)
        let localAlbum = "local-album-" + String(repeating: "b", count: 64)
        let requests = [(localTrack, "456"), ("123", localAlbum), (localTrack, localAlbum)].map {
            SongDownloadRequest(trackID: $0.0, albumID: $0.1, title: "Song", artistName: "Artist", albumName: "Album", artworkURL: nil)
        }

        let result = manager.submitRequests(requests)

        #expect(result.queued == 0)
        #expect(result.skipped == 3)
        #expect(manager.tasksPublisher.value.isEmpty)
        #expect(try database.allDownloadJobs().isEmpty)
    }

    @Test
    @MainActor
    func `mixed submissions still queue catalog tracks`() throws {
        let (sandbox, _, database, store) = try makeStoreComponents()
        _ = sandbox
        let manager = makeManager(database: database, store: store)
        manager.isPausedAll = true
        let local = SongDownloadRequest(
            trackID: "local-track-" + String(repeating: "a", count: 64),
            albumID: "local-album-" + String(repeating: "b", count: 64),
            title: "Local Song", artistName: "Artist", albumName: "Album", artworkURL: nil,
        )
        let catalog = SongDownloadRequest(trackID: "123", albumID: "456", title: "Catalog Song", artistName: "Artist", albumName: "Album", artworkURL: nil)

        let result = manager.submitRequests([local, catalog])

        #expect(result.queued == 1)
        #expect(result.skipped == 1)
        #expect(manager.tasksPublisher.value.map(\.trackID) == [catalog.trackID])
        #expect(try database.allDownloadJobs().map(\.trackID) == [catalog.trackID])
    }

    @Test
    @MainActor
    func `a local song remaining in a playlist after removal is not downloaded`() async throws {
        let (sandbox, _, database, store) = try makeStoreComponents()
        let track = try await sandbox.ingestTrack(
            makeMockTrack(trackID: "local-track-" + String(repeating: "a", count: 64)), into: database,
        )
        let playlist = try await database.createPlaylist(name: "Local songs")
        let entry = PlaylistEntry(trackID: track.trackID, title: track.title, artistName: track.artistName, albumID: track.albumID, albumTitle: track.albumTitle, artworkURL: nil)
        try await database.addEntry(entry, to: playlist.id)
        MusicLibraryTrackRemovalService(databaseManager: database.databaseManager).removeTrack(trackID: track.trackID)
        #expect(try database.track(byID: track.trackID) == nil)
        let savedPlaylist = try #require(try database.fetchPlaylist(id: playlist.id))
        #expect(savedPlaylist.entries.map(\.trackID) == [track.trackID])
        let manager = makeManager(database: database, store: store)

        let result = manager.submitRequests(savedPlaylist.entries.map {
            $0.downloadRequest(albumID: $0.albumID ?? "unknown", apiBaseURL: nil)
        })

        #expect(result.queued == 0)
        #expect(result.skipped == 1)
        #expect(manager.tasksPublisher.value.isEmpty)
        #expect(try database.allDownloadJobs().isEmpty)
    }

    @Test
    func `DownloadStore categorizes active and failed download records`() throws {
        let (sandbox, _, database, store) = try makeStoreComponents()
        _ = sandbox

        let activeRecord = DownloadJob(
            jobID: "dl-active",
            trackID: "track-active",
            albumID: "album",
            targetRelativePath: "album/track-active.m4a",
            title: "Active Track",
            artistName: "Artist",
            status: .downloading,
            progress: 0.5,
        )
        try database.upsertDownloadJob(activeRecord)

        let failedRecord = DownloadJob(
            jobID: "dl-failed",
            trackID: "track-failed",
            albumID: "album",
            targetRelativePath: "album/track-failed.m4a",
            title: "Failed Track",
            artistName: "Artist",
            status: .failed,
        )
        try database.upsertDownloadJob(failedRecord)

        let allIDs = Set(store.allRecords().map(\.jobID))
        #expect(allIDs == Set([activeRecord.jobID, failedRecord.jobID]))

        let activeIDs = Set(store.activeRecords().map(\.jobID))
        #expect(activeIDs == Set([activeRecord.jobID]))

        let failedIDs = Set(store.failedRecords().map(\.jobID))
        #expect(failedIDs == Set([failedRecord.jobID]))

        #expect(store.activeCount() == 1)
        #expect(store.hasRecord(trackID: activeRecord.trackID))
        #expect(store.hasRecord(trackID: failedRecord.trackID) == false)
        #expect(store.record(id: activeRecord.jobID)?.status == .downloading)
        #expect(store.record(trackID: "track-active")?.jobID == activeRecord.jobID)
    }

    @Test
    func `DownloadStore.deleteRecords removes jobs tied to the provided track IDs`() throws {
        let (sandbox, _, database, store) = try makeStoreComponents()
        _ = sandbox

        let record = DownloadJob(
            jobID: "dl-delete",
            trackID: "track-to-delete",
            albumID: "album",
            targetRelativePath: "album/track-to-delete.m4a",
            title: "To Delete",
            artistName: "Artist",
            status: .queued,
        )
        try database.upsertDownloadJob(record)

        store.deleteRecords(trackIDs: [record.trackID])
        #expect(store.record(trackID: record.trackID) == nil)
        #expect(store.allRecords().isEmpty)
    }

    @Test
    func `DownloadStore.upsert propagates state changes and clears active list`() throws {
        let (sandbox, _, database, store) = try makeStoreComponents()
        _ = sandbox

        let record = DownloadJob(
            jobID: "dl-update",
            trackID: "track-update",
            albumID: "album",
            targetRelativePath: "album/track-update.m4a",
            title: "Updated",
            artistName: "Artist",
            status: .queued,
        )
        try database.upsertDownloadJob(record)

        let failedRecord = DownloadJob(
            jobID: record.jobID,
            trackID: record.trackID,
            albumID: record.albumID,
            targetRelativePath: record.targetRelativePath,
            title: record.title,
            artistName: record.artistName,
            status: .failed,
        )
        store.upsert(failedRecord)

        #expect(store.record(id: record.jobID)?.status == .failed)
        #expect(store.activeRecords().isEmpty)
    }

    // MARK: - storageSize

    @Test
    func `storageSize returns total size from tracks table`() async throws {
        let sandbox = TestLibrarySandbox()
        let database = try sandbox.makeDatabase()
        let paths = database.paths
        let store = DownloadStore(database: database, paths: paths)

        let relativePath = "album1/track1.m4a"
        let track = makeMockTrack(
            trackID: "track-1",
            relativePath: relativePath,
            fileSizeBytes: 4096,
        )
        let ingestedTrack = try await sandbox.ingestTrack(track, into: database)

        let size = store.storageSize(
            forTrackIDs: Set(["track-1"]),
            audioDirectory: paths.audioDirectory,
        )
        #expect(size == ingestedTrack.fileSizeBytes)
    }

    @Test
    func `storageSize returns zero for unknown trackIDs`() throws {
        let sandbox = TestLibrarySandbox()
        let database = try sandbox.makeDatabase()
        let paths = database.paths
        let store = DownloadStore(database: database, paths: paths)

        let size = store.storageSize(
            forTrackIDs: Set(["nonexistent"]),
            audioDirectory: paths.audioDirectory,
        )
        #expect(size == 0)
    }

    @Test
    func `isDownloaded requires track record and real local file`() async throws {
        let sandbox = TestLibrarySandbox()
        let database = try sandbox.makeDatabase()
        let paths = database.paths
        let store = DownloadStore(database: database, paths: paths)

        // Track record exists but file does not
        let track = makeMockTrack(
            trackID: "track-4",
            relativePath: "album/track4.m4a",
            fileSizeBytes: 1000,
        )
        let ingestedMissingFileTrack = try await sandbox.ingestTrack(track, into: database)
        try FileManager.default.removeItem(
            at: paths.absoluteAudioURL(for: ingestedMissingFileTrack.relativePath),
        )

        #expect(store.isDownloaded(trackID: "track-4") == false)

        // No track record at all
        #expect(store.isDownloaded(trackID: "nonexistent") == false)

        // Track record with actual file
        let relativePath = "album/track5.m4a"
        let fileURL = paths.absoluteAudioURL(for: relativePath)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        try Data("audio".utf8).write(to: fileURL)

        let trackWithFile = makeMockTrack(
            trackID: "track-5",
            relativePath: relativePath,
            fileSizeBytes: 5,
        )
        _ = try await sandbox.ingestTrack(trackWithFile, into: database)

        #expect(store.isDownloaded(trackID: "track-5") == true)
    }

    // MARK: - playlistItemCount

    @Test
    func `playlistItemCount returns correct count`() async throws {
        let sandbox = TestLibrarySandbox()
        let database = try sandbox.makeDatabase()
        let playlist = try await database.createPlaylist(name: "Count Test")

        #expect(try database.playlistItemCount(for: playlist.id) == 0)

        try await database.addEntry(
            PlaylistEntry(trackID: "s1", title: "Song 1", artistName: "A"),
            to: playlist.id,
        )
        #expect(try database.playlistItemCount(for: playlist.id) == 1)

        try await database.addEntry(
            PlaylistEntry(trackID: "s2", title: "Song 2", artistName: "A"),
            to: playlist.id,
        )
        #expect(try database.playlistItemCount(for: playlist.id) == 2)
    }

    // MARK: - reconcileOnLaunch rehydration

    @Test
    @MainActor
    func `reconcileOnLaunch rehydrates downloading records as waiting`() throws {
        let sandbox = TestLibrarySandbox()
        let database = try sandbox.makeDatabase()
        let paths = database.paths
        let store = DownloadStore(database: database, paths: paths)

        let record = DownloadJob(
            jobID: "dl-active",
            trackID: "track-active",
            albumID: "album",
            targetRelativePath: "album/track.m4a",
            sourceURL: "https://example.com/audio.m4a",
            title: "Active Track",
            artistName: "Artist",
            status: .downloading,
            progress: 0.5,
        )
        store.upsert(record)

        let networkMonitor = NetworkMonitor()
        let apiClient = try APIClient(baseURL: #require(URL(string: "https://example.com")))
        let manager = DownloadManager(
            paths: paths,
            databaseManager: database.databaseManager,
            downloadStore: store,
            apiClient: apiClient,
            lyricsCacheStore: LyricsCacheStore(paths: paths),
            networkMonitor: networkMonitor,
            screenAwakeHandler: { _ in },
        )
        manager.reconcileOnLaunch()

        let tasks = manager.tasksPublisher.value
        #expect(tasks.count == 1)
        #expect(tasks.first?.trackID == "track-active")
        #expect(tasks.first?.state == .waiting)

        let reconciled = store.record(id: "dl-active")
        #expect(reconciled?.status == .queued || reconciled?.status == .waitingForNetwork)
        #expect(reconciled?.sourceURL == nil)
    }

    @Test
    @MainActor
    func `reconcileOnLaunch rehydrates queued records into active tasks`() throws {
        let sandbox = TestLibrarySandbox()
        let database = try sandbox.makeDatabase()
        let paths = database.paths
        let store = DownloadStore(database: database, paths: paths)

        let record = DownloadJob(
            jobID: "dl-queued",
            trackID: "track-queued",
            albumID: "album",
            targetRelativePath: "album/track-queued.m4a",
            sourceURL: "https://example.com/audio.m4a",
            title: "Queued Track",
            artistName: "Artist",
            status: .queued,
            progress: 0,
        )
        store.upsert(record)

        let networkMonitor = NetworkMonitor()
        let apiClient = try APIClient(baseURL: #require(URL(string: "https://example.com")))
        let manager = DownloadManager(
            paths: paths,
            databaseManager: database.databaseManager,
            downloadStore: store,
            apiClient: apiClient,
            lyricsCacheStore: LyricsCacheStore(paths: paths),
            networkMonitor: networkMonitor,
            screenAwakeHandler: { _ in },
        )
        manager.reconcileOnLaunch()

        let tasks = manager.tasksPublisher.value
        #expect(tasks.count == 1)
        #expect(tasks.first?.trackID == "track-queued")
        #expect(tasks.first?.state == .waiting)

        let dbRecord = store.record(id: "dl-queued")
        #expect(dbRecord?.status == .queued || dbRecord?.status == .waitingForNetwork)
    }

    @Test
    @MainActor
    func `reconcileOnLaunch infers managed paths for queued records without targetRelativePath`() throws {
        let sandbox = TestLibrarySandbox()
        let database = try sandbox.makeDatabase()
        let paths = database.paths
        let store = DownloadStore(database: database, paths: paths)

        let record = DownloadJob(
            jobID: "dl-no-path",
            trackID: "track-no-path",
            albumID: "unknown",
            targetRelativePath: "",
            title: "No Path Track",
            artistName: "Artist",
            status: .queued,
            progress: 0,
        )
        store.upsert(record)

        let networkMonitor = NetworkMonitor()
        let apiClient = try APIClient(baseURL: #require(URL(string: "https://example.com")))
        let manager = DownloadManager(
            paths: paths,
            databaseManager: database.databaseManager,
            downloadStore: store,
            apiClient: apiClient,
            lyricsCacheStore: LyricsCacheStore(paths: paths),
            networkMonitor: networkMonitor,
            screenAwakeHandler: { _ in },
        )
        manager.reconcileOnLaunch()

        let tasks = manager.tasksPublisher.value
        #expect(tasks.count == 1)
        #expect(tasks.first?.trackID == "track-no-path")
        #expect(tasks.first?.state == .waiting)
        #expect(tasks.first?.destinationRelativePath == "unknown/track-no-path.m4a")

        let dbRecord = store.record(id: "dl-no-path")
        #expect(dbRecord?.status == .queued || dbRecord?.status == .waitingForNetwork)
        #expect(dbRecord?.targetRelativePath == "unknown/track-no-path.m4a")
    }
}
