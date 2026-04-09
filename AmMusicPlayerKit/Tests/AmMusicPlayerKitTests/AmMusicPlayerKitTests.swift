@testable import AmMusicPlayerKit
import Testing

@Test func playbackStateIsActive() {
    #expect(PlaybackState.playing.isActive == true)
    #expect(PlaybackState.paused.isActive == true)
    #expect(PlaybackState.buffering.isActive == true)
    #expect(PlaybackState.idle.isActive == false)
    #expect(PlaybackState.error("test").isActive == false)
}
