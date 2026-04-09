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
    @Test func setTrack_seedsExpectedMetadata() throws {
        let publisher = MockNowPlayingStatePublisher()
        let manager = NowPlayingInfoManager(publisher: publisher)
        let item = try PlayerItem(
            id: "track-1",
            url: #require(URL(string: "https://example.com/track-1.mp3")),
            title: "Track 1",
            artist: "Artist 1",
            album: "Album 1",
            durationInSeconds: 245
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

    @Test func updateElapsedTime_republishesTrackMetadataWhenSinkWasCleared() throws {
        let publisher = MockNowPlayingStatePublisher()
        let manager = NowPlayingInfoManager(publisher: publisher)
        let item = try PlayerItem(
            id: "track-1",
            url: #require(URL(string: "https://example.com/track-1.mp3")),
            title: "Track 1",
            artist: "Artist 1",
            album: "Album 1",
            durationInSeconds: 245
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

    @Test func updateElapsedTime_omitsPlaybackProgressWhenDurationIsMissing() throws {
        let publisher = MockNowPlayingStatePublisher()
        let manager = NowPlayingInfoManager(publisher: publisher)
        let item = try PlayerItem(
            id: "track-1",
            url: #require(URL(string: "https://example.com/track-1.mp3")),
            title: "Track 1",
            artist: "Artist 1",
            album: "Album 1"
        )

        manager.setTrack(item)
        manager.updateElapsedTime(42)

        let info = try #require(publisher.nowPlayingInfo)
        #expect(info[MPNowPlayingInfoPropertyPlaybackProgress] == nil)
    }

    @Test func updateElapsedTime_omitsPlaybackProgressWhenDurationIsZero() throws {
        let publisher = MockNowPlayingStatePublisher()
        let manager = NowPlayingInfoManager(publisher: publisher)
        let item = try PlayerItem(
            id: "track-1",
            url: #require(URL(string: "https://example.com/track-1.mp3")),
            title: "Track 1",
            artist: "Artist 1",
            album: "Album 1",
            durationInSeconds: 0
        )

        manager.setTrack(item)
        manager.updateElapsedTime(42)

        let info = try #require(publisher.nowPlayingInfo)
        #expect(info[MPNowPlayingInfoPropertyPlaybackProgress] == nil)
    }

    @Test func updatePlaybackState_mapsStatesForSystemMediaCenter() {
        let publisher = MockNowPlayingStatePublisher()
        let manager = NowPlayingInfoManager(publisher: publisher)

        manager.updatePlaybackState(.playing)
        #expect(publisher.playbackState == .playing)

        manager.updatePlaybackState(.paused)
        #expect(publisher.playbackState == .paused)

        manager.updatePlaybackState(.idle)
        #expect(publisher.playbackState == .stopped)
    }

    @Test func clear_clearsPublishedInfoAndStopsPlayback() throws {
        let publisher = MockNowPlayingStatePublisher()
        let manager = NowPlayingInfoManager(publisher: publisher)
        let item = try PlayerItem(
            id: "track-1",
            url: #require(URL(string: "https://example.com/track-1.mp3")),
            title: "Track 1",
            artist: "Artist 1",
            album: "Album 1",
            durationInSeconds: 245
        )

        manager.setTrack(item)
        manager.updatePlaybackState(.playing)
        manager.clear()

        #expect(publisher.nowPlayingInfo == nil)
        #expect(publisher.playbackState == .stopped)
    }
}
