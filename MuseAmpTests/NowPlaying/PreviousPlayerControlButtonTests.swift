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
        let controller = try await makeControllerPlayingFirstTrack(sandbox: sandbox)
        let button = PreviousPlayerControlButton(playbackController: controller)
        try await Task.sleep(for: .milliseconds(100))
        #expect(controller.snapshot.history.isEmpty)
        #expect(button.isEnabled == false)

        controller.musicPlayer(MusicPlayer(), didUpdateTime: 5, duration: 180)
        try await Task.sleep(for: .milliseconds(100))

        #expect(button.isEnabled)
        #expect(controller.snapshot.currentTime < 3)
        withExtendedLifetime(sandbox) {}
    }

    @Test
    func `Previous disables again when time falls back under three seconds`() async throws {
        let sandbox = TestLibrarySandbox()
        let controller = try await makeControllerPlayingFirstTrack(sandbox: sandbox)
        let button = PreviousPlayerControlButton(playbackController: controller)

        controller.musicPlayer(MusicPlayer(), didUpdateTime: 8, duration: 180)
        try await Task.sleep(for: .milliseconds(100))
        #expect(button.isEnabled)

        controller.musicPlayer(MusicPlayer(), didUpdateTime: 1, duration: 180)
        try await Task.sleep(for: .milliseconds(100))
        #expect(button.isEnabled == false)
        withExtendedLifetime(sandbox) {}
    }

    // MARK: - Helpers

    private func makeControllerPlayingFirstTrack(sandbox: TestLibrarySandbox) async throws -> PlaybackController {
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
            player: MusicPlayer(engine: PreviousButtonTestEngine()),
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

/// Never plays audio or reports time on its own, so only the time updates
/// a test sends reach the playback controller.
@MainActor
private final class PreviousButtonTestEngine: AudioPlaybackEngine {
    private var mockRate: Float = 0
    private var mockCurrentTime: CMTime = .zero
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
