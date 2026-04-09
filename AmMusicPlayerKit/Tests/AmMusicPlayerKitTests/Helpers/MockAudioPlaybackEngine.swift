@testable import AmMusicPlayerKit
import AVFoundation

@MainActor
final class MockAudioPlaybackEngine: AudioPlaybackEngine {
    // MARK: - State Tracking

    var playCallCount = 0
    var pauseCallCount = 0
    var seekCallCount = 0
    var lastSeekTime: CMTime?
    var replaceItemCallCount = 0
    var lastReplacedItem: AVPlayerItem?
    var preloadCallCount = 0
    var lastPreloadedItem: AVPlayerItem?
    var removeTimeObserverCallCount = 0
    var addTimeObserverCallCount = 0
    var periodicTimeObserver: (@Sendable (CMTime) -> Void)?

    // MARK: - Configurable Returns

    var mockRate: Float = 0
    var mockCurrentTime: CMTime = .zero
    var mockCurrentItem: AVPlayerItem?

    // MARK: - Protocol

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
        replaceItemCallCount += 1
        lastReplacedItem = item
        mockCurrentItem = item
    }

    func play() {
        playCallCount += 1
        mockRate = 1.0
    }

    func pause() {
        pauseCallCount += 1
        mockRate = 0
    }

    func seek(to time: CMTime) async -> Bool {
        seekCallCount += 1
        lastSeekTime = time
        mockCurrentTime = time
        return true
    }

    func currentTime() -> CMTime {
        mockCurrentTime
    }

    func addPeriodicTimeObserver(
        forInterval _: CMTime,
        queue _: DispatchQueue?,
        using block: @escaping @Sendable (CMTime) -> Void
    ) -> Any {
        addTimeObserverCallCount += 1
        periodicTimeObserver = block
        return "mock-time-observer" as NSString
    }

    func removeTimeObserver(_: Any) {
        removeTimeObserverCallCount += 1
        periodicTimeObserver = nil
    }

    func preloadNextItem(_ item: AVPlayerItem?) {
        preloadCallCount += 1
        lastPreloadedItem = item
    }

    func simulatePeriodicTimeObserver(seconds: TimeInterval) {
        periodicTimeObserver?(CMTime(seconds: seconds, preferredTimescale: 600))
    }
}
