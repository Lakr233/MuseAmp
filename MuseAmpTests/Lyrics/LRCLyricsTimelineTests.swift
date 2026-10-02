import Foundation
@testable import MuseAmp
import Testing

@Suite(.serialized)
@MainActor
struct LyricTimelineTests {
    @Test
    func `LRC timeline parses timestamps, multiple tags, and offset`() {
        let timeline = LyricTimeline(lrc: """
        [ti:Example Song]
        [ar:Example Artist]
        [offset:500]
        [00:15.50][00:20.050]Chorus
        [00:10.00]Verse
        [invalid]
        """)

        // Positive offset shifts lyrics earlier: display time = tag time - offset.
        #expect(timeline.lines == [
            LyricLine(time: 0, text: ""),
            LyricLine(time: 9.5, text: "Verse"),
            LyricLine(time: 15.0, text: "Chorus"),
            LyricLine(time: 20.05 - 0.5, text: "Chorus"),
        ])
    }

    @Test
    func `LRC timeline delays lyrics for negative offset`() {
        let timeline = LyricTimeline(lrc: """
        [offset:-500]
        [00:10.00]Verse
        """)

        #expect(timeline.lines == [
            LyricLine(time: 0, text: ""),
            LyricLine(time: 10.5, text: "Verse"),
        ])
    }

    @Test
    func `LRC timeline clamps offset-adjusted times at zero`() {
        let timeline = LyricTimeline(lrc: """
        [offset:2000]
        [00:01.00]Line
        """)

        #expect(timeline.lines == [
            LyricLine(time: 0, text: "Line"),
        ])
    }

    @Test(arguments: [
        ("[00:01]One", 1.0),
        ("[00:01.2]One", 1.2),
        ("[00:01.23]One", 1.23),
        ("[00:01.234]One", 1.234),
    ])
    func `LRC timeline supports second fractions`(lrc: String, expectedTime: TimeInterval) {
        let timeline = LyricTimeline(lrc: lrc)

        #expect(timeline.lines == [
            LyricLine(time: 0, text: ""),
            LyricLine(time: expectedTime, text: "One"),
        ])
    }

    @Test
    func `LRC timeline has no active progress before first real line`() {
        let timeline = LyricTimeline(lrc: """
        [00:05.00]Intro
        [00:10.00]Verse
        """)

        let progress = timeline.progress(at: 4.99)

        #expect(progress?.index == 0)
        #expect(progress?.line == LyricLine(time: 0, text: ""))
    }

    @Test
    func `LRC timeline resolves active line progress between timestamps`() {
        let timeline = LyricTimeline(lrc: """
        [00:05.00]Intro
        [00:10.00]Verse
        [00:20.00]Chorus
        """)

        let progress = timeline.progress(at: 15)

        #expect(progress?.index == 2)
        #expect(progress?.line == LyricLine(time: 10, text: "Verse"))
        #expect(progress?.elapsed == 5)
        #expect(progress?.duration == 10)
        #expect(progress?.progress == 0.5)
    }

    @Test
    func `LRC timeline marks final line complete after it starts`() {
        let timeline = LyricTimeline(lrc: """
        [00:05.00]Intro
        [00:10.00]Outro
        """)

        let progress = timeline.progress(at: 30)

        #expect(progress?.index == 2)
        #expect(progress?.line == LyricLine(time: 10, text: "Outro"))
        #expect(progress?.duration == nil)
        #expect(progress?.progress == 1)
    }

    // MARK: - Continuation line splitting

    @Test
    func `LRC timeline assigns continuation lines to last timestamp`() {
        let timeline = LyricTimeline(lrc: "[00:05.00]Line one\nLine two\n[00:10.00]Line three")

        #expect(timeline.lines == [
            LyricLine(time: 0, text: ""),
            LyricLine(time: 5, text: "Line one"),
            LyricLine(time: 5, text: "Line two"),
            LyricLine(time: 10, text: "Line three"),
        ])
    }

    @Test
    func `LRC timeline splits text containing embedded newlines`() {
        let timeline = LyricTimeline(lrc: "[00:05.00]First\nSecond\nThird")

        #expect(timeline.lines == [
            LyricLine(time: 0, text: ""),
            LyricLine(time: 5, text: "First"),
            LyricLine(time: 5, text: "Second"),
            LyricLine(time: 5, text: "Third"),
        ])
    }

    @Test
    func `LRC timeline discards continuation lines before first timestamp`() {
        let timeline = LyricTimeline(lrc: "Orphan line\n[00:05.00]Real line")

        #expect(timeline.lines == [
            LyricLine(time: 0, text: ""),
            LyricLine(time: 5, text: "Real line"),
        ])
    }

    @Test
    func `LRC timeline ignores empty continuation lines`() {
        let timeline = LyricTimeline(lrc: "[00:05.00]Line one\n\n  \n[00:10.00]Line two")

        #expect(timeline.lines == [
            LyricLine(time: 0, text: ""),
            LyricLine(time: 5, text: "Line one"),
            LyricLine(time: 10, text: "Line two"),
        ])
    }

    @Test
    func `LRC timeline splits multiple continuation lines between timestamps`() {
        let timeline = LyricTimeline(lrc: """
        [00:05.00]Verse one
        Continuation A
        Continuation B
        [00:10.00]Verse two
        """)

        #expect(timeline.lines == [
            LyricLine(time: 0, text: ""),
            LyricLine(time: 5, text: "Verse one"),
            LyricLine(time: 5, text: "Continuation A"),
            LyricLine(time: 5, text: "Continuation B"),
            LyricLine(time: 10, text: "Verse two"),
        ])
    }

    // MARK: - Same-timestamp groups

    @Test
    func `lines sharing a timestamp are active together and anchor on the first`() {
        let timeline = LyricTimeline(lrc: """
        [00:05.00]Original
        [00:05.00]Translation
        [00:10.00]Next
        """)

        #expect(timeline.activeLineRange(at: 7) == 1 ..< 3)
        let progress = timeline.progress(at: 7)
        #expect(progress?.index == 1)
        #expect(progress?.duration == 5)
        #expect(timeline.activeLineRange(at: 12) == 3 ..< 4)
    }

    @Test
    func `continuation lines light up with their timestamped line`() throws {
        let parsed = LyricTimelineView.parseLyrics(from: "[00:05.00]Line one\nLine two\n[00:10.00]Line three")
        let timeline = try #require(parsed.timeline)

        #expect(timeline.activeLineRange(at: 6) == 1 ..< 3)

        let snapshot = LyricTimelineView.buildSnapshot(phase: .loaded(parsed), currentTime: 6)
        let activeTexts = snapshot.items.compactMap { item -> String? in
            guard case let .line(_, text, true) = item else { return nil }
            return text
        }
        #expect(activeTexts == ["Line one", "Line two"])
    }

    @Test
    func `lyrics stamped at one time are shown as static lyrics`() {
        let parsed = LyricTimelineView.parseLyrics(from: """
        [00:00.00]A
        [00:00.00]B
        [00:00.00]C
        """)

        #expect(parsed.timeline == nil)
        #expect(parsed.lines == ["A", "B", "C"])
    }

    @Test
    func `one timestamp followed by untimed lines is shown as static lyrics`() {
        let parsed = LyricTimelineView.parseLyrics(from: """
        [00:12.00]Header line
        Verse one
        Verse two
        """)

        #expect(parsed.timeline == nil)
        #expect(parsed.lines == ["Header line", "Verse one", "Verse two"])
    }

    // MARK: - Tags and timestamp formats

    @Test
    func `unsynced lyrics drop LRC ID tags but keep section markers`() {
        let parsed = LyricTimelineView.parseLyrics(from: """
        [ti:Header Test]
        [ar:Header Artist]
        [by:Someone]
        [offset:0]
        Plain one
        [Chorus]
        Plain two
        """)

        #expect(parsed.timeline == nil)
        #expect(parsed.lines == ["Plain one", "[Chorus]", "Plain two"])
    }

    @Test(arguments: [
        ("[00:01.2345]One\n[00:03.00]Two", 1.234),
        ("[00:01:23]One\n[00:03:00]Two", 1.23),
    ])
    func `timestamps with long fractions or a colon separator are synced`(lrc: String, expectedTime: TimeInterval) throws {
        let parsed = LyricTimelineView.parseLyrics(from: lrc)
        let timeline = try #require(parsed.timeline)

        #expect(timeline.lines == [
            LyricLine(time: 0, text: ""),
            LyricLine(time: expectedTime, text: "One"),
            LyricLine(time: 3, text: "Two"),
        ])
    }

    // MARK: - Seek targets

    @Test
    func `blank lead-in line is not a seek target`() {
        let timeline = LyricTimeline(lrc: """
        [00:05.00]Intro
        [00:08.00]
        [00:10.00]Verse
        """)

        #expect(timeline.lines.first == LyricLine(time: 0, text: ""))
        #expect(LyricTimelineView.seekTime(for: .line(0, "", true), in: timeline) == nil)
        #expect(LyricTimelineView.seekTime(for: .line(2, "", false), in: timeline) == nil)
        #expect(LyricTimelineView.seekTime(for: .line(1, "Intro", false), in: timeline) == 5)
        #expect(LyricTimelineView.seekTime(for: .line(3, "Verse", false), in: timeline) == 10)
    }
}
