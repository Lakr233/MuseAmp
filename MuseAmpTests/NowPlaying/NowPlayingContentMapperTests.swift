import Foundation
@testable import MuseAmp
import MuseAmpPlayerKit
import Testing

@Suite(.serialized)
struct NowPlayingContentMapperTests {
    @Test
    func `Mapper respects clean title preference explicitly`() {
        TrackTitleSanitizer.refresh(titles: ["Song - Live", "Other - Live"])
        let snapshot = PlaybackSnapshot(
            state: .paused,
            queue: [
                PlaybackTrack(
                    id: "track-1",
                    title: "Song - Live",
                    artistName: "Artist",
                    albumName: "Album",
                    albumID: "album-1",
                    durationInSeconds: 180,
                ),
            ],
            playerIndex: 0,
            currentTime: 30,
            duration: 180,
            repeatMode: .off,
            shuffled: false,
            source: nil,
            isCurrentTrackLiked: false,
            outputDevice: nil,
        )

        let cleaned = NowPlayingContentMapper.makeContent(
            from: snapshot,
            cleanTitleEnabled: true,
        )
        let raw = NowPlayingContentMapper.makeContent(
            from: snapshot,
            cleanTitleEnabled: false,
        )

        #expect(cleaned.title == "Song")
        #expect(raw.title == "Song - Live")
    }

    @Test
    func `Mapper returns placeholder content for empty snapshot`() {
        let content = NowPlayingContentMapper.makeContent(
            from: .empty,
            cleanTitleEnabled: true,
        )

        #expect(content.trackID.isEmpty)
        #expect(content.hasActiveTrack == false)
    }
}
