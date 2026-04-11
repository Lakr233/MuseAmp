@testable import AmMusic
import AmMusicDatabaseKit
import AmMusicPlayerKit
import Combine
import Foundation
import Testing

@Suite(.serialized)
@MainActor
struct PlaybackControllerTests {
    @Test
    func `PlaybackController prefers local file URLs`() async throws {
        let sandbox = TestLibrarySandbox()
        let locations = LibraryPaths(baseDirectory: sandbox.baseDirectory)
        try locations.ensureDirectoriesExist()

        let database = try sandbox.makeDatabase()
        let downloadStore = DownloadStore(database: database, paths: locations)
        let playlistStore = PlaylistStore(database: database)
        let apiClient = try APIClient(baseURL: #require(URL(string: "https://example.com")))

        let fileURL = try makeLocalAudioFile(
            locations: locations,
            relativePath: "Artist/Album/local-track.wav",
        )

        let controller = PlaybackController(
            apiClient: apiClient,
            database: database,
            downloadStore: downloadStore,
            metadataReader: EmbeddedMetadataReader(),
            paths: locations,
            playlistStore: playlistStore,
        )

        let track = PlaybackTrack(
            id: "local-track",
            title: "Local Track",
            artistName: "Artist",
            albumName: "Album",
            localFileURL: fileURL,
        )

        let started = await controller.play(tracks: [track], source: .library)

        #expect(started == true)
        #expect(controller.cachedItem(for: "local-track")?.url == fileURL)
    }

    @Test
    func `PlaybackController rejects non-local playback URLs`() async throws {
        let sandbox = TestLibrarySandbox()
        let database = try sandbox.makeDatabase()
        let locations = LibraryPaths(baseDirectory: sandbox.baseDirectory)
        let downloadStore = DownloadStore(database: database, paths: locations)
        let playlistStore = PlaylistStore(database: database)
        let apiClient = try APIClient(baseURL: #require(URL(string: "https://example.com")))

        let controller = PlaybackController(
            apiClient: apiClient,
            database: database,
            downloadStore: downloadStore,
            metadataReader: EmbeddedMetadataReader(),
            paths: locations,
            playlistStore: playlistStore,
        )

        let track = PlaybackTrack(id: "remote-track", title: "Remote Track", artistName: "Artist")
        let started = await controller.play(tracks: [track], source: .search(query: "remote"))

        #expect(started == false)
        #expect(controller.cachedItem(for: "remote-track") == nil)
    }

    @Test
    func `PlaybackController skips non-local tracks and starts next local track`() async throws {
        let sandbox = TestLibrarySandbox()
        let locations = LibraryPaths(baseDirectory: sandbox.baseDirectory)
        try locations.ensureDirectoriesExist()
        let database = try sandbox.makeDatabase()
        let downloadStore = DownloadStore(database: database, paths: locations)
        let playlistStore = PlaylistStore(database: database)
        let apiClient = try APIClient(baseURL: #require(URL(string: "https://example.com")))

        let controller = PlaybackController(
            apiClient: apiClient,
            database: database,
            downloadStore: downloadStore,
            metadataReader: EmbeddedMetadataReader(),
            paths: locations,
            playlistStore: playlistStore,
        )

        let localURL = try makeLocalAudioFile(
            locations: locations,
            relativePath: "Artist/Album/Track 2.wav",
        )

        let tracks = [
            PlaybackTrack(id: "remote-track", title: "Remote Track", artistName: "Artist"),
            PlaybackTrack(id: "local-track", title: "Local Track", artistName: "Artist", localFileURL: localURL),
        ]

        let started = await controller.play(tracks: tracks, startAt: 0, source: .playlist(UUID()))

        #expect(started == true)
        #expect(controller.snapshot.currentTrack?.id == "local-track")
        #expect(controller.snapshot.history.isEmpty)
        #expect(controller.snapshot.upcoming.isEmpty)
    }

    @Test
    func `PlaybackController playNext and addToQueue update upcoming queue with local files`() async throws {
        let sandbox = TestLibrarySandbox()
        let locations = LibraryPaths(baseDirectory: sandbox.baseDirectory)
        try locations.ensureDirectoriesExist()
        let database = try sandbox.makeDatabase()
        let downloadStore = DownloadStore(database: database, paths: locations)
        let playlistStore = PlaylistStore(database: database)
        let apiClient = try APIClient(baseURL: #require(URL(string: "https://example.com")))

        let controller = PlaybackController(
            apiClient: apiClient,
            database: database,
            downloadStore: downloadStore,
            metadataReader: EmbeddedMetadataReader(),
            paths: locations,
            playlistStore: playlistStore,
        )

        let oneURL = try makeLocalAudioFile(locations: locations, relativePath: "Artist/Album/One.wav")
        let twoURL = try makeLocalAudioFile(locations: locations, relativePath: "Artist/Album/Two.wav")
        let priorityURL = try makeLocalAudioFile(locations: locations, relativePath: "Artist/Album/Priority.wav")
        let queuedURL = try makeLocalAudioFile(locations: locations, relativePath: "Artist/Album/Queued.wav")

        let baseTracks = [
            PlaybackTrack(id: "one", title: "One", artistName: "Artist", localFileURL: oneURL),
            PlaybackTrack(id: "two", title: "Two", artistName: "Artist", localFileURL: twoURL),
        ]
        _ = await controller.play(tracks: baseTracks, source: .library)

        let priority = PlaybackTrack(id: "priority", title: "Priority", artistName: "Artist", localFileURL: priorityURL)
        let queued = PlaybackTrack(id: "queued", title: "Queued", artistName: "Artist", localFileURL: queuedURL)

        let playNextResult = await controller.playNext([priority])
        let addToQueueCount = await controller.addToQueue([queued])

        guard case let .queued(playNextCount) = playNextResult else {
            Issue.record("Expected .queued, got \(playNextResult)")
            return
        }
        #expect(playNextCount == 1)
        #expect(addToQueueCount == 1)
        #expect(controller.snapshot.upcoming.map(\.id) == ["priority", "two", "queued"])
    }

    @Test
    func `PlaybackController playNext publishes one snapshot update`() async throws {
        let sandbox = TestLibrarySandbox()
        let locations = LibraryPaths(baseDirectory: sandbox.baseDirectory)
        try locations.ensureDirectoriesExist()
        let database = try sandbox.makeDatabase()
        let downloadStore = DownloadStore(database: database, paths: locations)
        let playlistStore = PlaylistStore(database: database)
        let apiClient = try APIClient(baseURL: #require(URL(string: "https://example.com")))

        let controller = PlaybackController(
            apiClient: apiClient,
            database: database,
            downloadStore: downloadStore,
            metadataReader: EmbeddedMetadataReader(),
            paths: locations,
            playlistStore: playlistStore,
        )

        let oneURL = try makeLocalAudioFile(locations: locations, relativePath: "Artist/Album/Base-One.wav")
        let twoURL = try makeLocalAudioFile(locations: locations, relativePath: "Artist/Album/Base-Two.wav")
        let priorityURL = try makeLocalAudioFile(locations: locations, relativePath: "Artist/Album/Base-Priority.wav")

        let baseTracks = [
            PlaybackTrack(id: "base-one", title: "Base One", artistName: "Artist", localFileURL: oneURL),
            PlaybackTrack(id: "base-two", title: "Base Two", artistName: "Artist", localFileURL: twoURL),
        ]
        _ = await controller.play(tracks: baseTracks, source: .library)
        await settlePlaybackController()

        let baselineUpcoming = controller.snapshot.upcoming.map(\.id)

        var snapshots: [PlaybackSnapshot] = []
        let cancellable = controller.$snapshot
            .dropFirst()
            .filter { $0.upcoming.map(\.id) != baselineUpcoming }
            .sink { snapshots.append($0) }

        let priority = PlaybackTrack(
            id: "base-priority",
            title: "Base Priority",
            artistName: "Artist",
            localFileURL: priorityURL,
        )

        let result = await controller.playNext([priority])
        await settlePlaybackController()

        withExtendedLifetime(cancellable) {
            guard case let .queued(count) = result else {
                Issue.record("Expected .queued, got \(result)")
                return
            }
            #expect(count == 1)
            #expect(snapshots.count >= 1)
            #expect(snapshots.last?.upcoming.map(\.id) == ["base-priority", "base-two"])
        }
    }

    @Test
    func `PlaybackController persists relative paths and restores local queue`() async throws {
        let sandbox = TestLibrarySandbox()
        let locations = LibraryPaths(baseDirectory: sandbox.baseDirectory)
        try locations.ensureDirectoriesExist()
        let database = try sandbox.makeDatabase()
        let downloadStore = DownloadStore(database: database, paths: locations)
        let playlistStore = PlaylistStore(database: database)
        let apiClient = try APIClient(baseURL: #require(URL(string: "https://example.com")))

        let sessionStore = PlaybackSessionStore(fileURL: locations.playbackStateURL)
        let controller = PlaybackController(
            apiClient: apiClient,
            database: database,
            downloadStore: downloadStore,
            metadataReader: EmbeddedMetadataReader(),
            paths: locations,
            playlistStore: playlistStore,
            sessionStore: sessionStore,
        )

        let firstURL = try makeLocalAudioFile(locations: locations, relativePath: "Artist/Album/First.wav")
        let secondURL = try makeLocalAudioFile(locations: locations, relativePath: "Artist/Album/Second.wav")
        let tracks = [
            PlaybackTrack(id: "first", title: "First", artistName: "Artist", albumName: "Album", localFileURL: firstURL),
            PlaybackTrack(id: "second", title: "Second", artistName: "Artist", albumName: "Album", localFileURL: secondURL),
        ]

        let started = await controller.play(tracks: tracks, startAt: 1, source: .playlist(UUID()))
        #expect(started == true)

        controller.persistPlaybackState()

        let data = try Data(contentsOf: locations.playbackStateURL)
        let decoded = try JSONDecoder().decode(PersistedPlaybackSession.self, from: data)
        #expect(decoded.queue.map(\.localRelativePath) == [Optional("Artist/Album/Second.wav")])
        #expect(decoded.queue.allSatisfy { $0.localRelativePath?.hasPrefix("/") == false })

        let restoredController = PlaybackController(
            apiClient: apiClient,
            database: database,
            downloadStore: downloadStore,
            metadataReader: EmbeddedMetadataReader(),
            paths: locations,
            playlistStore: playlistStore,
            sessionStore: sessionStore,
        )

        let restored = await restoredController.restorePersistedPlaybackIfNeeded()

        #expect(restored == true)
        #expect(restoredController.snapshot.state == .paused)
        #expect(restoredController.snapshot.currentTrack?.id == "second")
        #expect(restoredController.cachedItem(for: "second")?.url == secondURL)
    }

    @Test
    func `PlaybackController play replaces paused queue with new tracks`() async throws {
        let sandbox = TestLibrarySandbox()
        let locations = LibraryPaths(baseDirectory: sandbox.baseDirectory)
        try locations.ensureDirectoriesExist()
        let database = try sandbox.makeDatabase()
        let downloadStore = DownloadStore(database: database, paths: locations)
        let playlistStore = PlaylistStore(database: database)
        let apiClient = try APIClient(baseURL: #require(URL(string: "https://example.com")))

        let controller = PlaybackController(
            apiClient: apiClient,
            database: database,
            downloadStore: downloadStore,
            metadataReader: EmbeddedMetadataReader(),
            paths: locations,
            playlistStore: playlistStore,
        )

        let oldURL = try makeLocalAudioFile(locations: locations, relativePath: "Artist/Album/Old.wav")
        let newOneURL = try makeLocalAudioFile(locations: locations, relativePath: "Artist/Album/NewOne.wav")
        let newTwoURL = try makeLocalAudioFile(locations: locations, relativePath: "Artist/Album/NewTwo.wav")

        let oldTrack = PlaybackTrack(id: "old", title: "Old", artistName: "Artist", localFileURL: oldURL)
        _ = await controller.play(tracks: [oldTrack], source: .library)
        controller.pause()

        #expect(controller.latestSnapshot.state == .paused)
        #expect(controller.latestSnapshot.currentTrack?.id == "old")

        let newTracks = [
            PlaybackTrack(id: "new-one", title: "New One", artistName: "Artist", localFileURL: newOneURL),
            PlaybackTrack(id: "new-two", title: "New Two", artistName: "Artist", localFileURL: newTwoURL),
        ]
        let started = await controller.play(tracks: newTracks, startAt: 0, source: .album(id: "new-album"))

        #expect(started == true)
        #expect(controller.latestSnapshot.currentTrack?.id == "new-one")
        #expect(controller.latestSnapshot.upcoming.map(\.id) == ["new-two"])
    }

    @Test
    func `PlaybackController suppresses UI time publishing while backgrounded`() async throws {
        let sandbox = TestLibrarySandbox()
        let locations = LibraryPaths(baseDirectory: sandbox.baseDirectory)
        try locations.ensureDirectoriesExist()
        let database = try sandbox.makeDatabase()
        let downloadStore = DownloadStore(database: database, paths: locations)
        let playlistStore = PlaylistStore(database: database)
        let apiClient = try APIClient(baseURL: #require(URL(string: "https://example.com")))

        let fileURL = try makeLocalAudioFile(
            locations: locations,
            relativePath: "Artist/Album/Background.wav",
        )

        let controller = PlaybackController(
            apiClient: apiClient,
            database: database,
            downloadStore: downloadStore,
            metadataReader: EmbeddedMetadataReader(),
            paths: locations,
            playlistStore: playlistStore,
        )

        let started = await controller.play(
            tracks: [
                PlaybackTrack(
                    id: "background-track",
                    title: "Background Track",
                    artistName: "Artist",
                    albumName: "Album",
                    localFileURL: fileURL,
                ),
            ],
            source: .library,
        )
        #expect(started == true)

        let publishedTime = controller.snapshot.currentTime
        controller.setUIPublishingSuspended(true)
        controller.musicPlayer(MusicPlayer(), didUpdateTime: 9, duration: 30)

        #expect(controller.snapshot.currentTime == publishedTime)
    }

    private func makeLocalAudioFile(
        locations: LibraryPaths,
        relativePath: String,
    ) throws -> URL {
        let fileURL = locations.absoluteAudioURL(for: relativePath)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        try makeSilentWAVData().write(to: fileURL)
        return fileURL
    }

    private func makeSilentWAVData(
        sampleRate: UInt32 = 8000,
        duration: TimeInterval = 0.25,
    ) -> Data {
        let channelCount: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let bytesPerSample = UInt32(bitsPerSample / 8)
        let frameCount = UInt32(max(Int((Double(sampleRate) * duration).rounded()), 1))
        let byteRate = sampleRate * UInt32(channelCount) * bytesPerSample
        let blockAlign = channelCount * UInt16(bytesPerSample)
        let dataSize = frameCount * UInt32(blockAlign)
        let riffChunkSize = 36 + dataSize

        var data = Data()
        data.append("RIFF".data(using: .ascii)!)
        data.append(littleEndianBytes(riffChunkSize))
        data.append("WAVE".data(using: .ascii)!)
        data.append("fmt ".data(using: .ascii)!)
        data.append(littleEndianBytes(UInt32(16)))
        data.append(littleEndianBytes(UInt16(1)))
        data.append(littleEndianBytes(channelCount))
        data.append(littleEndianBytes(sampleRate))
        data.append(littleEndianBytes(byteRate))
        data.append(littleEndianBytes(blockAlign))
        data.append(littleEndianBytes(bitsPerSample))
        data.append("data".data(using: .ascii)!)
        data.append(littleEndianBytes(dataSize))
        data.append(Data(count: Int(dataSize)))
        return data
    }

    private func littleEndianBytes<T: FixedWidthInteger>(_ value: T) -> Data {
        var littleEndianValue = value.littleEndian
        return Data(bytes: &littleEndianValue, count: MemoryLayout<T>.size)
    }

    private func settlePlaybackController() async {
        for _ in 0 ..< 3 {
            await Task.yield()
        }
    }
}
