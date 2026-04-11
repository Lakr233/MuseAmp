//
//  LocalizationTests.swift
//  AmMusicPlayerKit
//
//  Created by @Lakr233 on 2026/04/11.
//

@testable import AmMusicPlayerKit
import Foundation
import Testing

@MainActor
struct LocalizationTests {
    @Test
    func `MusicPlayer uses localized default like title`() {
        let player = MusicPlayer(engine: MockAudioPlaybackEngine())
        #expect(player.likeCommandLocalizedTitle == String(localized: "Like", bundle: .module))
    }
}
