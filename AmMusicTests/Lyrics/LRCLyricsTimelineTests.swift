@testable import AmMusic
import Foundation
import Testing

@Suite(.serialized)
@MainActor
struct LRCLyricsTimelineTests {
    @Test
    func `LRC timeline parses timestamps, multiple tags, and offset`() {
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

    @Test(arguments: [
        ("[00:01]One", 1.0),
        ("[00:01.2]One", 1.2),
        ("[00:01.23]One", 1.23),
        ("[00:01.234]One", 1.234),
    ])
    func `LRC timeline supports second fractions`(lrc: String, expectedTime: TimeInterval) {
        let timeline = LRCLyricsTimeline(lrc: lrc)

        #expect(timeline.lines == [
            .init(time: 0, text: ""),
            .init(time: expectedTime, text: "One"),
        ])
    }

    @Test
    func `LRC timeline has no active progress before first real line`() {
        let timeline = LRCLyricsTimeline(lrc: """
        [00:05.00]Intro
        [00:10.00]Verse
        """)

        let progress = timeline.progress(at: 4.99)

        #expect(progress?.index == 0)
        #expect(progress?.line == .init(time: 0, text: ""))
    }

    @Test
    func `LRC timeline resolves active line progress between timestamps`() {
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

    @Test
    func `LRC timeline marks final line complete after it starts`() {
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

    // MARK: - Continuation line splitting

    @Test
    func `LRC timeline assigns continuation lines to last timestamp`() {
        let timeline = LRCLyricsTimeline(lrc: "[00:05.00]Line one\nLine two\n[00:10.00]Line three")

        #expect(timeline.lines == [
            .init(time: 0, text: ""),
            .init(time: 5, text: "Line one"),
            .init(time: 5, text: "Line two"),
            .init(time: 10, text: "Line three"),
        ])
    }

    @Test
    func `LRC timeline splits text containing embedded newlines`() {
        let timeline = LRCLyricsTimeline(lrc: "[00:05.00]First\nSecond\nThird")

        #expect(timeline.lines == [
            .init(time: 0, text: ""),
            .init(time: 5, text: "First"),
            .init(time: 5, text: "Second"),
            .init(time: 5, text: "Third"),
        ])
    }

    @Test
    func `LRC timeline discards continuation lines before first timestamp`() {
        let timeline = LRCLyricsTimeline(lrc: "Orphan line\n[00:05.00]Real line")

        #expect(timeline.lines == [
            .init(time: 0, text: ""),
            .init(time: 5, text: "Real line"),
        ])
    }

    @Test
    func `LRC timeline ignores empty continuation lines`() {
        let timeline = LRCLyricsTimeline(lrc: "[00:05.00]Line one\n\n  \n[00:10.00]Line two")

        #expect(timeline.lines == [
            .init(time: 0, text: ""),
            .init(time: 5, text: "Line one"),
            .init(time: 10, text: "Line two"),
        ])
    }

    @Test
    func `LRC timeline splits multiple continuation lines between timestamps`() {
        let timeline = LRCLyricsTimeline(lrc: """
        [00:05.00]Verse one
        Continuation A
        Continuation B
        [00:10.00]Verse two
        """)

        #expect(timeline.lines == [
            .init(time: 0, text: ""),
            .init(time: 5, text: "Verse one"),
            .init(time: 5, text: "Continuation A"),
            .init(time: 5, text: "Continuation B"),
            .init(time: 10, text: "Verse two"),
        ])
    }
}
