@testable import AmMusic
import AmMusicDatabaseKit
import Foundation
import Testing

@Suite(.serialized)
struct DownloadStoreFacadeTests {
    private func makeStoreComponents() throws -> (
        TestLibrarySandbox,
        LibraryPaths,
        MusicLibraryDatabase,
        DownloadStore
    ) {
        let sandbox = TestLibrarySandbox()
        let database = try sandbox.makeDatabase()
        let paths = database.paths
        let store = DownloadStore(database: database, paths: paths)
        return (sandbox, paths, database, store)
    }

    @Test("DownloadStore categorizes active and failed download records")
    func downloadStoreCategorizesRecords() throws {
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
            progress: 0.5
        )
        try database.upsertDownloadJob(activeRecord)

        let failedRecord = DownloadJob(
            jobID: "dl-failed",
            trackID: "track-failed",
            albumID: "album",
            targetRelativePath: "album/track-failed.m4a",
            title: "Failed Track",
            artistName: "Artist",
            status: .failed
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

    @Test("DownloadStore.deleteRecords removes jobs tied to the provided track IDs")
    func deleteRecordsRemovesMatchingEntries() throws {
        let (sandbox, _, database, store) = try makeStoreComponents()
        _ = sandbox

        let record = DownloadJob(
            jobID: "dl-delete",
            trackID: "track-to-delete",
            albumID: "album",
            targetRelativePath: "album/track-to-delete.m4a",
            title: "To Delete",
            artistName: "Artist",
            status: .queued
        )
        try database.upsertDownloadJob(record)

        store.deleteRecords(trackIDs: [record.trackID])
        #expect(store.record(trackID: record.trackID) == nil)
        #expect(store.allRecords().isEmpty)
    }

    @Test("DownloadStore.upsert propagates state changes and clears active list")
    func upsertUpdatesRecordState() throws {
        let (sandbox, _, database, store) = try makeStoreComponents()
        _ = sandbox

        let record = DownloadJob(
            jobID: "dl-update",
            trackID: "track-update",
            albumID: "album",
            targetRelativePath: "album/track-update.m4a",
            title: "Updated",
            artistName: "Artist",
            status: .queued
        )
        try database.upsertDownloadJob(record)

        let failedRecord = DownloadJob(
            jobID: record.jobID,
            trackID: record.trackID,
            albumID: record.albumID,
            targetRelativePath: record.targetRelativePath,
            title: record.title,
            artistName: record.artistName,
            status: .failed
        )
        store.upsert(failedRecord)

        #expect(store.record(id: record.jobID)?.status == .failed)
        #expect(store.activeRecords().isEmpty)
    }

    // MARK: - storageSize

    @Test("storageSize returns total size from tracks table")
    func storageSizeForTracksTable() async throws {
        let sandbox = TestLibrarySandbox()
        let database = try sandbox.makeDatabase()
        let paths = database.paths
        let store = DownloadStore(database: database, paths: paths)

        let fileContent = Data(repeating: 0xAB, count: 4096)
        let audioDir = paths.audioDirectory
        let relativePath = "album1/track1.m4a"
        let fileURL = audioDir.appendingPathComponent(relativePath, isDirectory: false)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileContent.write(to: fileURL)

        let track = makeMockTrack(
            trackID: "track-1",
            relativePath: relativePath,
            fileSizeBytes: 4096
        )
        _ = try await sandbox.ingestTrack(track, into: database)

        let size = store.storageSize(
            forTrackIDs: Set(["track-1"]),
            audioDirectory: audioDir
        )
        #expect(size == 4096)
    }

    @Test("storageSize returns zero for unknown trackIDs")
    func storageSizeZeroForUnknownTracks() throws {
        let sandbox = TestLibrarySandbox()
        let database = try sandbox.makeDatabase()
        let paths = database.paths
        let store = DownloadStore(database: database, paths: paths)

        let size = store.storageSize(
            forTrackIDs: Set(["nonexistent"]),
            audioDirectory: paths.audioDirectory
        )
        #expect(size == 0)
    }

    @Test("isDownloaded requires track record and real local file")
    func isDownloadedRequiresTrackAndFile() async throws {
        let sandbox = TestLibrarySandbox()
        let database = try sandbox.makeDatabase()
        let paths = database.paths
        let store = DownloadStore(database: database, paths: paths)

        // Track record exists but file does not
        let track = makeMockTrack(
            trackID: "track-4",
            relativePath: "album/track4.m4a",
            fileSizeBytes: 1000
        )
        let ingestedMissingFileTrack = try await sandbox.ingestTrack(track, into: database)
        try FileManager.default.removeItem(
            at: paths.absoluteAudioURL(for: ingestedMissingFileTrack.relativePath)
        )

        #expect(store.isDownloaded(trackID: "track-4") == false)

        // No track record at all
        #expect(store.isDownloaded(trackID: "nonexistent") == false)

        // Track record with actual file
        let relativePath = "album/track5.m4a"
        let fileURL = paths.absoluteAudioURL(for: relativePath)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("audio".utf8).write(to: fileURL)

        let trackWithFile = makeMockTrack(
            trackID: "track-5",
            relativePath: relativePath,
            fileSizeBytes: 5
        )
        _ = try await sandbox.ingestTrack(trackWithFile, into: database)

        #expect(store.isDownloaded(trackID: "track-5") == true)
    }

    // MARK: - playlistItemCount

    @Test("playlistItemCount returns correct count")
    func playlistItemCount() async throws {
        let sandbox = TestLibrarySandbox()
        let database = try sandbox.makeDatabase()
        let playlist = try await database.createPlaylist(name: "Count Test")

        #expect(try database.playlistItemCount(for: playlist.id) == 0)

        try await database.addEntry(
            PlaylistEntry(trackID: "s1", title: "Song 1", artistName: "A"),
            to: playlist.id
        )
        #expect(try database.playlistItemCount(for: playlist.id) == 1)

        try await database.addEntry(
            PlaylistEntry(trackID: "s2", title: "Song 2", artistName: "A"),
            to: playlist.id
        )
        #expect(try database.playlistItemCount(for: playlist.id) == 2)
    }

    // MARK: - reconcileOnLaunch rehydration

    @Test("reconcileOnLaunch rehydrates downloading records as waiting")
    @MainActor
    func reconcileRehydratesDownloadingRecords() throws {
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
            progress: 0.5
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
            screenAwakeHandler: { _ in }
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

    @Test("reconcileOnLaunch rehydrates queued records into active tasks")
    @MainActor
    func reconcileRehydratesQueuedRecords() throws {
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
            progress: 0
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
            screenAwakeHandler: { _ in }
        )
        manager.reconcileOnLaunch()

        let tasks = manager.tasksPublisher.value
        #expect(tasks.count == 1)
        #expect(tasks.first?.trackID == "track-queued")
        #expect(tasks.first?.state == .waiting)

        let dbRecord = store.record(id: "dl-queued")
        #expect(dbRecord?.status == .queued || dbRecord?.status == .waitingForNetwork)
    }

    @Test("reconcileOnLaunch infers managed paths for queued records without targetRelativePath")
    @MainActor
    func reconcileInfersQueuedRecordPath() throws {
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
            progress: 0
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
            screenAwakeHandler: { _ in }
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
