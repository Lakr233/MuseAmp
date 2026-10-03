import Foundation

nonisolated enum LyricParser {
    static func parse(lrc: String) -> [LyricLine] {
        let offset = parseOffset(from: lrc)
        var parsedLines: [(order: Int, line: LyricLine)] = []
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
                    line: LyricLine(time: time, text: text),
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
                    line: LyricLine(time: adjustedTime, text: text),
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

        return [LyricLine(time: 0, text: "")] + sortedLines
    }

    /// Display lines for lyrics without usable timestamps. LRC ID tags such as
    /// `[ti:]`, `[ar:]` or `[offset:]` are metadata, not lyrics, so they are
    /// dropped; bracketed section markers such as `[Chorus]` are kept.
    static func plainLines(from text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0.wholeMatch(of: idTagLinePattern) == nil }
    }
}

private nonisolated extension LyricParser {
    /// `[mm:ss]`, `[mm:ss.x…]` or `[mm:ss:xx]`. Fractions longer than
    /// milliseconds are accepted and truncated by `parseTime`.
    static var timestampPattern: Regex<(Substring, Substring, Substring, Substring?)> {
        #/\[(\d+):(\d{1,2})(?:[.:](\d+))?\]/#
    }

    static var idTagLinePattern: Regex<Substring> {
        #/(?i)\[(?:ti|ar|al|au|by|re|ve|la|id|tool|length|offset|#)\s*:[^\]]*\]/#
    }

    static var offsetPattern: Regex<(Substring, Substring)> {
        #/\[offset:([+-]?\d+)\]/#
    }

    static var tagLinePattern: Regex<Substring> {
        #/^\[.+\]$/#
    }

    static func splitMultilineEntries(_ lines: [LyricLine]) -> [LyricLine] {
        lines.flatMap { line -> [LyricLine] in
            let parts = line.text
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard parts.count > 1 else { return [line] }
            return parts.map { LyricLine(time: line.time, text: $0) }
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
