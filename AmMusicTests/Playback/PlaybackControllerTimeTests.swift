@testable import AmMusic
import AmMusicDatabaseKit
@testable import AmMusicPlayerKit
import AVFoundation
import Combine
import CoreMedia
import Foundation
import Testing

@Suite(.serialized)
@MainActor
struct PlaybackControllerTimeTests {
    @Test
    func `didUpdateTime updates latestSnapshot but not published snapshot`() async throws {
        let (controller, _) = try await makePlayingController()

        let publishedTime = controller.snapshot.currentTime
        controller.musicPlayer(MusicPlayer(), didUpdateTime: 42, duration: 180)

        #expect(controller.latestSnapshot.currentTime == 42)
        #expect(controller.latestSnapshot.duration == 180)
        #expect(controller.snapshot.currentTime == publishedTime)
    }

    @Test
    func `didUpdateTime does not update when UI publishing suspended`() async throws {
        let (controller, _) = try await makePlayingController()

        controller.setUIPublishingSuspended(true)
        controller.musicPlayer(MusicPlayer(), didUpdateTime: 42, duration: 180)

        #expect(controller.latestSnapshot.currentTime != 42)
    }

    @Test
    func `playbackTimeSubject emits on time update`() async throws {
        let (controller, _) = try await makePlayingController()

        var emissions: [(TimeInterval, TimeInterval)] = []
        let cancellable = controller.playbackTimeSubject
            .sink { emissions.append(($0.currentTime, $0.duration)) }

        controller.musicPlayer(MusicPlayer(), didUpdateTime: 15, duration: 200)
        controller.musicPlayer(MusicPlayer(), didUpdateTime: 15.25, duration: 200)

        withExtendedLifetime(cancellable) {
            #expect(emissions.count == 2)
            #expect(emissions[0].0 == 15)
            #expect(emissions[1].0 == 15.25)
        }
    }

    @Test
    func `persist uses current player time not stale snapshot`() async throws {
        let sandbox = TestLibrarySandbox()
        let locations = LibraryPaths(baseDirectory: sandbox.baseDirectory)
        try locations.ensureDirectoriesExist()
        let database = try sandbox.makeDatabase()
        let downloadStore = DownloadStore(database: database, paths: locations)
        let playlistStore = PlaylistStore(database: database)
        let apiClient = try APIClient(baseURL: #require(URL(string: "https://example.com")))
        let engine = TimeTestMockEngine()
        let player = MusicPlayer(engine: engine)

        let controller = PlaybackController(
            apiClient: apiClient,
            database: database,
            downloadStore: downloadStore,
            metadataReader: EmbeddedMetadataReader(),
            paths: locations,
            playlistStore: playlistStore,
            player: player,
        )

        let fileURL = try makeLocalAudioFile(
            locations: locations,
            relativePath: "Artist/Album/Persist.wav",
        )
        let track = PlaybackTrack(
            id: "persist-track",
            title: "Persist Track",
            artistName: "Artist",
            albumName: "Album",
            localFileURL: fileURL,
        )

        _ = await controller.play(tracks: [track], source: .library)

        engine.mockCurrentTime = CMTimeMakeWithSeconds(88, preferredTimescale: 600)
        controller.persistPlaybackState()

        let data = try Data(contentsOf: locations.playbackStateURL)
        let decoded = try JSONDecoder().decode(PersistedPlaybackSession.self, from: data)
        #expect(decoded.currentTime == 88)
    }

    @Test
    func `previous restart refreshes snapshot with time zero`() async throws {
        let sandbox = TestLibrarySandbox()
        let locations = LibraryPaths(baseDirectory: sandbox.baseDirectory)
        try locations.ensureDirectoriesExist()
        let database = try sandbox.makeDatabase()
        let downloadStore = DownloadStore(database: database, paths: locations)
        let playlistStore = PlaylistStore(database: database)
        let apiClient = try APIClient(baseURL: #require(URL(string: "https://example.com")))
        let engine = TimeTestMockEngine()
        let player = MusicPlayer(engine: engine)

        let controller = PlaybackController(
            apiClient: apiClient,
            database: database,
            downloadStore: downloadStore,
            metadataReader: EmbeddedMetadataReader(),
            paths: locations,
            playlistStore: playlistStore,
            player: player,
        )

        let fileURL = try makeLocalAudioFile(
            locations: locations,
            relativePath: "Artist/Album/Restart.wav",
        )
        let track = PlaybackTrack(
            id: "restart-track",
            title: "Restart Track",
            artistName: "Artist",
            albumName: "Album",
            localFileURL: fileURL,
        )

        _ = await controller.play(tracks: [track], source: .library)
        engine.mockCurrentTime = CMTimeMakeWithSeconds(10, preferredTimescale: 600)

        controller.previous()

        #expect(controller.snapshot.currentTime == 0)
    }

    @Test
    func `event driven snapshot publishes immediately`() async throws {
        let (controller, _) = try await makePlayingController()

        var snapshots: [PlaybackSnapshot] = []
        let cancellable = controller.$snapshot
            .dropFirst()
            .sink { snapshots.append($0) }

        controller.setRepeatMode(.queue)

        withExtendedLifetime(cancellable) {
            #expect(snapshots.count >= 1)
            #expect(snapshots.last?.repeatMode == .queue)
        }
    }

    // MARK: - Helpers

    private func makePlayingController() async throws -> (PlaybackController, TestLibrarySandbox) {
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

        let fileURL = try makeLocalAudioFile(
            locations: locations,
            relativePath: "Artist/Album/TimeTest.wav",
        )
        let track = PlaybackTrack(
            id: "time-test",
            title: "Time Test",
            artistName: "Artist",
            albumName: "Album",
            localFileURL: fileURL,
        )

        _ = await controller.play(tracks: [track], source: .library)
        return (controller, sandbox)
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
}

@MainActor
private final class TimeTestMockEngine: AudioPlaybackEngine {
    var mockRate: Float = 0
    var mockCurrentTime: CMTime = .zero
    var mockCurrentItem: AVPlayerItem?

    var rate: Float {
        mockRate
    }

    var currentAVItem: AVPlayerItem? {
        mockCurrentItem
    }

    var mediaCenterPlayer: AVPlayer? {
        nil
    }

    func replaceCurrentItem(with item: AVPlayerItem?) {
        mockCurrentItem = item
    }

    func play() {
        mockRate = 1
    }

    func pause() {
        mockRate = 0
    }

    func seek(to time: CMTime) async -> Bool {
        mockCurrentTime = time
        return true
    }

    func currentTime() -> CMTime {
        mockCurrentTime
    }

    func addPeriodicTimeObserver(
        forInterval _: CMTime,
        queue _: DispatchQueue?,
        using _: @escaping @Sendable (CMTime) -> Void,
    ) -> Any {
        "mock-time-observer" as NSString
    }

    func removeTimeObserver(_: Any) {}
    func preloadNextItem(_: AVPlayerItem?) {}
    func hasAdvancedToPreloadedItem() -> Bool {
        false
    }

    func advanceToPreloadedItem() -> Bool {
        false
    }

    func clearPreloadedReference() {}
}
