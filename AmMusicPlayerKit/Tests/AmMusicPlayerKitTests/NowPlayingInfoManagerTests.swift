//
//  NowPlayingInfoManagerTests.swift
//  AmMusicPlayerKit
//
//  Created by @Lakr233 on 2026/04/11.
//

@testable import AmMusicPlayerKit
import Foundation
import MediaPlayer
import Testing

@MainActor
final class MockNowPlayingStatePublisher: NowPlayingStatePublishing {
    var nowPlayingInfo: [String: Any]?
    var playbackState: MPNowPlayingPlaybackState = .stopped
}

@MainActor
struct NowPlayingInfoManagerTests {
    @Test func `set track seeds expected metadata`() throws {
        let publisher = MockNowPlayingStatePublisher()
        let manager = NowPlayingInfoManager(publisher: publisher)
        let item = try PlayerItem(
            id: "track-1",
            url: #require(URL(string: "https://example.com/track-1.mp3")),
            title: "Track 1",
            artist: "Artist 1",
            album: "Album 1",
            durationInSeconds: 245,
        )

        manager.setTrack(item)

        let info = try #require(publisher.nowPlayingInfo)
        #expect(info[MPMediaItemPropertyTitle] as? String == "Track 1")
        #expect(info[MPMediaItemPropertyArtist] as? String == "Artist 1")
        #expect(info[MPMediaItemPropertyAlbumTitle] as? String == "Album 1")
        #expect(info[MPMediaItemPropertyPlaybackDuration] as? TimeInterval == 245)
        #expect(info[MPNowPlayingInfoPropertyExternalContentIdentifier] as? String == "track-1")
        #expect(info[MPNowPlayingInfoPropertyMediaType] as? UInt == .some(MPNowPlayingInfoMediaType.audio.rawValue))
        #expect(info[MPNowPlayingInfoPropertyPlaybackProgress] as? TimeInterval == 0)
    }

    @Test func `update elapsed time republishes track metadata when sink was cleared`() throws {
        let publisher = MockNowPlayingStatePublisher()
        let manager = NowPlayingInfoManager(publisher: publisher)
        let item = try PlayerItem(
            id: "track-1",
            url: #require(URL(string: "https://example.com/track-1.mp3")),
            title: "Track 1",
            artist: "Artist 1",
            album: "Album 1",
            durationInSeconds: 245,
        )

        manager.setTrack(item)
        publisher.nowPlayingInfo = nil

        manager.updateElapsedTime(42)

        let info = try #require(publisher.nowPlayingInfo)
        #expect(info[MPMediaItemPropertyTitle] as? String == "Track 1")
        #expect(info[MPMediaItemPropertyArtist] as? String == "Artist 1")
        #expect(info[MPMediaItemPropertyAlbumTitle] as? String == "Album 1")
        #expect(info[MPMediaItemPropertyPlaybackDuration] as? TimeInterval == 245)
        #expect(info[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? TimeInterval == 42)
        #expect(info[MPNowPlayingInfoPropertyPlaybackProgress] as? TimeInterval == (42.0 / 245.0))
    }

    @Test func `update elapsed time omits playback progress when duration is missing`() throws {
        let publisher = MockNowPlayingStatePublisher()
        let manager = NowPlayingInfoManager(publisher: publisher)
        let item = try PlayerItem(
            id: "track-1",
            url: #require(URL(string: "https://example.com/track-1.mp3")),
            title: "Track 1",
            artist: "Artist 1",
            album: "Album 1",
        )

        manager.setTrack(item)
        manager.updateElapsedTime(42)

        let info = try #require(publisher.nowPlayingInfo)
        #expect(info[MPNowPlayingInfoPropertyPlaybackProgress] == nil)
    }

    @Test func `update elapsed time omits playback progress when duration is zero`() throws {
        let publisher = MockNowPlayingStatePublisher()
        let manager = NowPlayingInfoManager(publisher: publisher)
        let item = try PlayerItem(
            id: "track-1",
            url: #require(URL(string: "https://example.com/track-1.mp3")),
            title: "Track 1",
            artist: "Artist 1",
            album: "Album 1",
            durationInSeconds: 0,
        )

        manager.setTrack(item)
        manager.updateElapsedTime(42)

        let info = try #require(publisher.nowPlayingInfo)
        #expect(info[MPNowPlayingInfoPropertyPlaybackProgress] == nil)
    }

    @Test func `update playback state maps states for system media center`() {
        let publisher = MockNowPlayingStatePublisher()
        let manager = NowPlayingInfoManager(publisher: publisher)

        manager.updatePlaybackState(.playing)
        #expect(publisher.playbackState == .playing)

        manager.updatePlaybackState(.paused)
        #expect(publisher.playbackState == .paused)

        manager.updatePlaybackState(.idle)
        #expect(publisher.playbackState == .stopped)
    }

    @Test func `clear clears published info and stops playback`() throws {
        let publisher = MockNowPlayingStatePublisher()
        let manager = NowPlayingInfoManager(publisher: publisher)
        let item = try PlayerItem(
            id: "track-1",
            url: #require(URL(string: "https://example.com/track-1.mp3")),
            title: "Track 1",
            artist: "Artist 1",
            album: "Album 1",
            durationInSeconds: 245,
        )

        manager.setTrack(item)
        manager.updatePlaybackState(.playing)
        manager.clear()

        #expect(publisher.nowPlayingInfo == nil)
        #expect(publisher.playbackState == .stopped)
    }
}
