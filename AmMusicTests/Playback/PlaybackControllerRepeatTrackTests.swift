@testable import AmMusic
import AmMusicDatabaseKit
@testable import AmMusicPlayerKit
import AVFoundation
import CoreMedia
import Foundation
import Testing

@Suite(.serialized)
@MainActor
struct PlaybackControllerRepeatTrackTests {
    @Test
    func `PlaybackController resets current time when repeat-track restarts the same song`() async throws {
        let sandbox = TestLibrarySandbox()
        let locations = LibraryPaths(baseDirectory: sandbox.baseDirectory)
        try locations.ensureDirectoriesExist()
        let database = try sandbox.makeDatabase()
        let downloadStore = DownloadStore(database: database, paths: locations)
        let playlistStore = PlaylistStore(database: database)
        let apiClient = try APIClient(baseURL: #require(URL(string: "https://example.com")))
        let engine = PlaybackControllerMockAudioPlaybackEngine()
        let player = MusicPlayer(engine: engine)

        let metadataReader = EmbeddedMetadataReader()
        let controller = PlaybackController(
            apiClient: apiClient,
            database: database,
            downloadStore: downloadStore,
            metadataReader: metadataReader,
            paths: locations,
            playlistStore: playlistStore,
            player: player,
        )

        let fileURL = try makeLocalAudioFile(
            locations: locations,
            relativePath: "Artist/Album/Repeat.wav",
        )
        let track = PlaybackTrack(
            id: "repeat-track",
            title: "Repeat Track",
            artistName: "Artist",
            albumName: "Album",
            localFileURL: fileURL,
        )

        let started = await controller.play(tracks: [track], source: .library)
        #expect(started == true)

        controller.musicPlayer(player, didUpdateTime: 55, duration: 60)
        #expect(controller.latestSnapshot.currentTime == 55)

        player.repeatMode = .track
        engine.mockCurrentTime = CMTimeMakeWithSeconds(55, preferredTimescale: 600)

        let currentItem = try #require(player.currentItem)
        controller.musicPlayer(player, didTransitionTo: currentItem, reason: .natural)

        #expect(controller.snapshot.currentTime == 0)
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
        try Data("test".utf8).write(to: fileURL)
        return fileURL
    }
}

@MainActor
private final class PlaybackControllerMockAudioPlaybackEngine: AudioPlaybackEngine {
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
