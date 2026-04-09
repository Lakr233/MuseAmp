@testable import AmMusicPlayerKit
import MediaPlayer
import Testing

@MainActor
final class MockMediaCenterBackend: MediaCenterBackend {
    var nowPlayingInfo: [String: Any]?
    var playbackState: MPNowPlayingPlaybackState = .stopped
    let commandCenter = MPRemoteCommandCenter.shared()
    private(set) var activationCount = 0

    func activateSessionIfPossible() {
        activationCount += 1
    }
}

@MainActor
struct MediaCenterCoordinatorTests {
    @Test func delegatesInfoStateAndActivationToInjectedBackend() {
        let backend = MockMediaCenterBackend()
        let coordinator = MediaCenterCoordinator(backend: backend, backendKind: .legacy)

        coordinator.nowPlayingInfo = [MPMediaItemPropertyTitle: "Track"]
        coordinator.playbackState = .playing
        coordinator.activateSessionIfPossible()

        #expect(backend.nowPlayingInfo?[MPMediaItemPropertyTitle] as? String == "Track")
        #expect(backend.playbackState == .playing)
        #expect(backend.activationCount == 1)
        #expect(coordinator.commandCenter === backend.commandCenter)
    }

    @Test func usesLegacyBackendForMockEngine() {
        let engine = MockAudioPlaybackEngine()
        let coordinator = MediaCenterCoordinator(engine: engine)

        #expect(coordinator.backendKind == .legacy)
    }
}
