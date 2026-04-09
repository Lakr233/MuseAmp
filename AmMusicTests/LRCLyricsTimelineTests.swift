@testable import AmMusic
import Foundation
import Testing

@Suite(.serialized)
@MainActor
struct LRCLyricsTimelineTests {
    @Test("LRC timeline parses timestamps, multiple tags, and offset")
    func parsesTimeline() {
        let timeline = LRCLyricsTimeline(lrc: """
        [ti:Example Song]
        [ar:Example Artist]
        [offset:500]
        [00:15.50][00:20.050]Chorus
        [00:10.00]Verse
        [invalid]
        """)

        #expect(timeline.lines == [
            .init(time: 0, text: ""),
            .init(time: 10.5, text: "Verse"),
            .init(time: 16.0, text: "Chorus"),
            .init(time: 20.55, text: "Chorus"),
        ])
    }

    @Test("LRC timeline supports second fractions", arguments: [
        ("[00:01]One", 1.0),
        ("[00:01.2]One", 1.2),
        ("[00:01.23]One", 1.23),
        ("[00:01.234]One", 1.234),
    ])
    func parsesFractionalSeconds(lrc: String, expectedTime: TimeInterval) {
        let timeline = LRCLyricsTimeline(lrc: lrc)

        #expect(timeline.lines == [
            .init(time: 0, text: ""),
            .init(time: expectedTime, text: "One"),
        ])
    }

    @Test("LRC timeline has no active progress before first real line")
    func noActiveProgressBeforeFirstLine() {
        let timeline = LRCLyricsTimeline(lrc: """
        [00:05.00]Intro
        [00:10.00]Verse
        """)

        let progress = timeline.progress(at: 4.99)

        #expect(progress?.index == 0)
        #expect(progress?.line == .init(time: 0, text: ""))
    }

    @Test("LRC timeline resolves active line progress between timestamps")
    func resolvesLineProgress() {
        let timeline = LRCLyricsTimeline(lrc: """
        [00:05.00]Intro
        [00:10.00]Verse
        [00:20.00]Chorus
        """)

        let progress = timeline.progress(at: 15)

        #expect(progress?.index == 2)
        #expect(progress?.line == .init(time: 10, text: "Verse"))
        #expect(progress?.elapsed == 5)
        #expect(progress?.duration == 10)
        #expect(progress?.progress == 0.5)
    }

    @Test("LRC timeline marks final line complete after it starts")
    func finalLineIsComplete() {
        let timeline = LRCLyricsTimeline(lrc: """
        [00:05.00]Intro
        [00:10.00]Outro
        """)

        let progress = timeline.progress(at: 30)

        #expect(progress?.index == 2)
        #expect(progress?.line == .init(time: 10, text: "Outro"))
        #expect(progress?.duration == nil)
        #expect(progress?.progress == 1)
    }
}
