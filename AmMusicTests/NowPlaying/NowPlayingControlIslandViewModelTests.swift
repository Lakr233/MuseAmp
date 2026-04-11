@testable import AmMusic
import AmMusicPlayerKit
import Testing

@Suite(.serialized)
@MainActor
struct NowPlayingControlIslandViewModelTests {
    @Test
    func `Control island shows AirPods Pro symbol for AirPods Pro routes`() {
        let viewModel = NowPlayingControlIslandViewModel()
        let snapshot = makeSnapshot(
            outputDevice: PlaybackOutputDevice(name: "AirPods Pro", kind: .bluetooth),
        )

        let presentation = viewModel.apply(snapshot: snapshot)

        #expect(presentation.content.routeName == "AirPods Pro")
        #expect(presentation.content.routeSymbolName == "airpodspro")
    }

    @Test
    func `Control island shows speaker symbol for built-in speaker`() {
        let viewModel = NowPlayingControlIslandViewModel()
        let snapshot = makeSnapshot(
            outputDevice: PlaybackOutputDevice(name: "iPhone", kind: .builtInSpeaker),
        )

        let presentation = viewModel.apply(snapshot: snapshot)

        #expect(presentation.content.routeSymbolName == "speaker.wave.2.fill")
    }

    @Test
    func `Control island shows TV symbol for Apple TV AirPlay routes`() {
        let viewModel = NowPlayingControlIslandViewModel()
        let snapshot = makeSnapshot(
            outputDevice: PlaybackOutputDevice(name: "Living Room TV", kind: .airPlay),
        )

        let presentation = viewModel.apply(snapshot: snapshot)

        #expect(presentation.content.routeSymbolName == "tv.fill")
    }
}

private func makeSnapshot(outputDevice: PlaybackOutputDevice?) -> PlaybackSnapshot {
    PlaybackSnapshot(
        state: .paused,
        queue: [],
        playerIndex: nil,
        currentTime: 0,
        duration: 0,
        repeatMode: .off,
        shuffled: false,
        source: nil,
        isCurrentTrackLiked: false,
        outputDevice: outputDevice,
    )
}
