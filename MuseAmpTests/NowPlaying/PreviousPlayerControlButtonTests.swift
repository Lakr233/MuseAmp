import AVFoundation
import CoreMedia
import Foundation
@testable import MuseAmp
import MuseAmpDatabaseKit
@testable import MuseAmpPlayerKit
import Testing
import UIKit

@Suite(.serialized)
@MainActor
struct PreviousPlayerControlButtonTests {
    @Test
    func `Previous enables once the first track plays past three seconds`() async throws {
        let sandbox = TestLibrarySandbox()
        let engine = PreviousButtonTestEngine()
        let controller = try await makeControllerPlayingFirstTrack(sandbox: sandbox, engine: engine)
        let button = PreviousPlayerControlButton(playbackController: controller)
        try await waitUntil(button.isEnabled == false)
        #expect(controller.snapshot.history.isEmpty)

        report(time: 5, to: controller, engine: engine)
        #expect(controller.snapshot.currentTime < 3)

        try await waitUntil(button.isEnabled)
        withExtendedLifetime(sandbox) {}
    }

    @Test
    func `Previous disables again when time falls back under three seconds`() async throws {
        let sandbox = TestLibrarySandbox()
        let engine = PreviousButtonTestEngine()
        let controller = try await makeControllerPlayingFirstTrack(sandbox: sandbox, engine: engine)
        let button = PreviousPlayerControlButton(playbackController: controller)

        report(time: 8, to: controller, engine: engine)
        try await waitUntil(button.isEnabled)

        report(time: 1, to: controller, engine: engine)
        try await waitUntil(button.isEnabled == false)
        withExtendedLifetime(sandbox) {}
    }

    // MARK: - Helpers

    /// Moves the engine's clock before reporting the tick, as the real
    /// player does, so a snapshot refresh after the tick keeps the time.
    private func report(time: TimeInterval, to controller: PlaybackController, engine: PreviousButtonTestEngine) {
        engine.mockCurrentTime = CMTime(seconds: time, preferredTimescale: 600)
        controller.musicPlayer(MusicPlayer(), didUpdateTime: time, duration: 180)
    }

    /// The button applies state on the next main-queue turn, and suites run
    /// in parallel, so the wait has a deadline instead of a fixed sleep.
    private func waitUntil(
        _ condition: @autoclosure () -> Bool,
        sourceLocation: SourceLocation = #_sourceLocation,
    ) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(condition(), sourceLocation: sourceLocation)
    }

    private func makeControllerPlayingFirstTrack(
        sandbox: TestLibrarySandbox,
        engine: PreviousButtonTestEngine,
    ) async throws -> PlaybackController {
        let locations = LibraryPaths(baseDirectory: sandbox.baseDirectory)
        try locations.ensureDirectoriesExist()
        let database = try sandbox.makeDatabase()
        let apiClient = try APIClient(baseURL: #require(URL(string: "https://example.com")))
        let controller = PlaybackController(
            apiClient: apiClient,
            database: database,
            downloadStore: DownloadStore(database: database, paths: locations),
            metadataReader: EmbeddedMetadataReader(),
            paths: locations,
            playlistStore: PlaylistStore(database: database),
            player: MusicPlayer(engine: engine),
        )

        let fileURL = locations.absoluteAudioURL(for: "Artist/Album/First.wav")
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        try makeSilentWAVData().write(to: fileURL)
        let track = PlaybackTrack(
            id: "first-track",
            title: "First Track",
            artistName: "Artist",
            albumName: "Album",
            localFileURL: fileURL,
        )

        _ = await controller.play(tracks: [track], source: .library)
        controller.setRepeatMode(.off)
        return controller
    }

    private func makeSilentWAVData() -> Data {
        let sampleRate: UInt32 = 8000
        let channelCount: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let blockAlign = channelCount * (bitsPerSample / 8)
        let dataSize = UInt32(sampleRate / 4) * UInt32(blockAlign)

        var data = Data()
        data.append(Data("RIFF".utf8))
        data.append(littleEndianBytes(36 + dataSize))
        data.append(Data("WAVEfmt ".utf8))
        data.append(littleEndianBytes(UInt32(16)))
        data.append(littleEndianBytes(UInt16(1)))
        data.append(littleEndianBytes(channelCount))
        data.append(littleEndianBytes(sampleRate))
        data.append(littleEndianBytes(sampleRate * UInt32(blockAlign)))
        data.append(littleEndianBytes(blockAlign))
        data.append(littleEndianBytes(bitsPerSample))
        data.append(Data("data".utf8))
        data.append(littleEndianBytes(dataSize))
        data.append(Data(count: Int(dataSize)))
        return data
    }

    private func littleEndianBytes<T: FixedWidthInteger>(_ value: T) -> Data {
        var littleEndianValue = value.littleEndian
        return Data(bytes: &littleEndianValue, count: MemoryLayout<T>.size)
    }
}

/// Never plays audio or advances its clock on its own, so only the times a
/// test sets reach the playback controller.
@MainActor
private final class PreviousButtonTestEngine: AudioPlaybackEngine {
    private var mockRate: Float = 0
    var mockCurrentTime: CMTime = .zero
    private var mockCurrentItem: AVPlayerItem?

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
        "previous-button-time-observer" as NSString
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
