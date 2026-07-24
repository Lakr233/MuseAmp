import Foundation

nonisolated enum TVLyricParser {
    static func parse(lrc: String) -> [TVLyricLine] {
        let offset = parseOffset(from: lrc)
        var parsedLines: [(order: Int, line: TVLyricLine)] = []
        var lastAdjustedTime: TimeInterval?

        for rawLine in lrc.components(separatedBy: .newlines) {
            let timestamps = rawLine.matches(of: timestampPattern)

            if timestamps.isEmpty {
                let text = rawLine.trimmingCharacters(in: .whitespaces)
                guard !text.isEmpty,
                      text.wholeMatch(of: tagLinePattern) == nil,
                      let time = lastAdjustedTime
                else {
                    continue
                }
                parsedLines.append((
                    order: parsedLines.count,
                    line: TVLyricLine(time: time, text: text),
                ))
                continue
            }

            let text = rawLine
                .replacing(timestampPattern, with: "")
                .trimmingCharacters(in: .whitespaces)

            for timestamp in timestamps {
                guard let time = parseTime(
                    minutes: String(timestamp.output.1),
                    seconds: String(timestamp.output.2),
                    fraction: String(timestamp.output.3 ?? ""),
                ) else {
                    continue
                }

                let adjustedTime = max(0, time - offset)
                lastAdjustedTime = adjustedTime
                parsedLines.append((
                    order: parsedLines.count,
                    line: TVLyricLine(time: adjustedTime, text: text),
                ))
            }
        }

        let sortedLines = splitMultilineEntries(
            parsedLines
                .sorted {
                    if $0.line.time == $1.line.time {
                        return $0.order < $1.order
                    }
                    return $0.line.time < $1.line.time
                }
                .map(\.line),
        )

        guard let firstLine = sortedLines.first, firstLine.time > 0 else {
            return sortedLines
        }

        return [TVLyricLine(time: 0, text: "")] + sortedLines
    }
}

private nonisolated extension TVLyricParser {
    static var timestampPattern: Regex<(Substring, Substring, Substring, Substring?)> {
        #/\[(\d+):(\d{1,2})(?:\.(\d{1,3}))?\]/#
    }

    static var offsetPattern: Regex<(Substring, Substring)> {
        #/\[offset:([+-]?\d+)\]/#
    }

    static var tagLinePattern: Regex<Substring> {
        #/^\[.+\]$/#
    }

    static func splitMultilineEntries(_ lines: [TVLyricLine]) -> [TVLyricLine] {
        lines.flatMap { line -> [TVLyricLine] in
            let parts = line.text
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard parts.count > 1 else { return [line] }
            return parts.map { TVLyricLine(time: line.time, text: $0) }
        }
    }

    /// LRC `[offset:]` is in milliseconds; a positive value shifts lyrics
    /// earlier (display time = tag time - offset). The last tag wins.
    static func parseOffset(from lrc: String) -> TimeInterval {
        guard let match = lrc.matches(of: offsetPattern).last,
              let value = Int(match.output.1)
        else {
            return 0
        }
        return TimeInterval(value) / 1000
    }

    static func parseTime(
        minutes: String,
        seconds: String,
        fraction: String,
    ) -> TimeInterval? {
        guard let minutesValue = TimeInterval(minutes),
              let secondsValue = TimeInterval(seconds)
        else {
            return nil
        }

        let fractionalValue: TimeInterval = switch fraction.count {
        case 0:
            0
        case 1:
            TimeInterval(fraction).map { $0 / 10 } ?? 0
        case 2:
            TimeInterval(fraction).map { $0 / 100 } ?? 0
        default:
            TimeInterval(fraction.prefix(3)).map { $0 / 1000 } ?? 0
        }

        return (minutesValue * 60) + secondsValue + fractionalValue
    }
}
