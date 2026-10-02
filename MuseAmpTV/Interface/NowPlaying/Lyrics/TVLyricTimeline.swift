import Foundation

nonisolated struct TVLyricTimeline: Sendable, Equatable {
    let lines: [TVLyricLine]

    nonisolated init(lrc: String) {
        lines = TVLyricParser.parse(lrc: lrc)
    }

    /// Whether the timestamps can drive a highlight: lines with text must
    /// span at least two distinct times. Lyrics stamped at a single time
    /// (every line `[00:00.00]`, or one stamp followed by untimed lines)
    /// carry no timing and should be shown as static lyrics.
    var isSynced: Bool {
        var firstTime: TimeInterval?
        for line in lines where !line.text.isEmpty {
            guard let time = firstTime else {
                firstTime = line.time
                continue
            }
            if line.time != time {
                return true
            }
        }
        return false
    }

    /// The lines active at `currentTime`: every line sharing the latest
    /// timestamp at or before it. Translations and continuation lines share
    /// their original line's timestamp, so the whole group is active together.
    func activeLineRange(at currentTime: TimeInterval) -> Range<Int>? {
        let lastIndex = lastLineIndex(atOrBefore: currentTime)
        guard lastIndex >= 0 else { return nil }

        let groupTime = lines[lastIndex].time
        var firstIndex = lastIndex
        while firstIndex > 0, lines[firstIndex - 1].time == groupTime {
            firstIndex -= 1
        }
        return firstIndex ..< lastIndex + 1
    }

    private func lastLineIndex(atOrBefore currentTime: TimeInterval) -> Int {
        var lowerBound = 0
        var upperBound = lines.count

        while lowerBound < upperBound {
            let midpoint = lowerBound + (upperBound - lowerBound) / 2
            if lines[midpoint].time <= currentTime {
                lowerBound = midpoint + 1
            } else {
                upperBound = midpoint
            }
        }

        return lowerBound - 1
    }
}
