import Foundation

nonisolated struct LyricTimeline: Sendable, Equatable {
    let lines: [LyricLine]

    nonisolated init(lrc: String) {
        lines = LyricParser.parse(lrc: lrc)
    }

    func progress(at currentTime: TimeInterval) -> LyricProgress? {
        guard !lines.isEmpty else { return nil }

        let index = activeLineIndex(at: currentTime)
        guard index >= 0 else { return nil }

        let line = lines[index]
        let elapsed = max(0, currentTime - line.time)

        guard index + 1 < lines.count else {
            return LyricProgress(line: line, index: index, elapsed: elapsed, duration: nil, progress: 1)
        }

        let duration = max(lines[index + 1].time - line.time, 0)
        let progress = duration > 0 ? min(max(elapsed / duration, 0), 1) : 1
        return LyricProgress(line: line, index: index, elapsed: elapsed, duration: duration, progress: progress)
    }

    private func activeLineIndex(at currentTime: TimeInterval) -> Int {
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
