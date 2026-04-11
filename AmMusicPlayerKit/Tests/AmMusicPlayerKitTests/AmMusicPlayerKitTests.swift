//
//  AmMusicPlayerKitTests.swift
//  AmMusicPlayerKit
//
//  Created by @Lakr233 on 2026/04/11.
//

@testable import AmMusicPlayerKit
import Testing

@Test func `playback state is active`() {
    #expect(PlaybackState.playing.isActive == true)
    #expect(PlaybackState.paused.isActive == true)
    #expect(PlaybackState.buffering.isActive == true)
    #expect(PlaybackState.idle.isActive == false)
    #expect(PlaybackState.error("test").isActive == false)
}
