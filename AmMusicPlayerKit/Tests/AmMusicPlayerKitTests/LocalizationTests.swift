@testable import AmMusicPlayerKit
import Foundation
import Testing

@MainActor
struct LocalizationTests {
    @Test("MusicPlayer uses localized default like title")
    func musicPlayerDefaultLikeTitle() {
        let player = MusicPlayer(engine: MockAudioPlaybackEngine())
        #expect(player.likeCommandLocalizedTitle == String(localized: "Like", bundle: .module))
    }
}
