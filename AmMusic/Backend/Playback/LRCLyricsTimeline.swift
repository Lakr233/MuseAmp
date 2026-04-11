//
//  LRCLyricsTimeline.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import Foundation

nonisolated struct LRCLyricsTimeline: Equatable {
    struct Line: Equatable {
        let time: TimeInterval
        let text: String
    }

    struct Progress: Equatable {
        let line: Line
        let index: Int
        let elapsed: TimeInterval
        let duration: TimeInterval?
        let progress: Double
    }

    let lines: [Line]

    init(lrc: String) {
        lines = Self.parse(lrc: lrc)
    }

    func progress(at currentTime: TimeInterval) -> Progress? {
        guard !lines.isEmpty else {
            return nil
        }

        let index = activeLineIndex(at: currentTime)
        guard index >= 0 else {
            return nil
        }

        let line = lines[index]
        let elapsed = max(0, currentTime - line.time)
        let nextLine = lines.indices.contains(index + 1) ? lines[index + 1] : nil

        if let nextLine {
            let duration = max(nextLine.time - line.time, 0)
            let progress: Double = if duration > 0 {
                min(max(elapsed / duration, 0), 1)
            } else {
                1
            }

            return Progress(
                line: line,
                index: index,
                elapsed: elapsed,
                duration: duration,
                progress: progress,
            )
        }

        return Progress(
            line: line,
            index: index,
            elapsed: elapsed,
            duration: nil,
            progress: 1,
        )
    }
}

private nonisolated extension LRCLyricsTimeline {
    static let timestampPattern = #/\[(\d+):(\d{1,2})(?:\.(\d{1,3}))?\]/#
    static let offsetPattern = #/\[offset:([+-]?\d+)\]/#
    static let tagLinePattern = #/^\[.+\]$/#

    static func parse(lrc: String) -> [Line] {
        let offset = parseOffset(from: lrc)
        var parsedLines: [(order: Int, line: Line)] = []
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
                    line: Line(time: time, text: text),
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

                let adjustedTime = time + offset
                lastAdjustedTime = adjustedTime
                parsedLines.append((
                    order: parsedLines.count,
                    line: Line(time: adjustedTime, text: text),
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

        return [Line(time: 0, text: "")] + sortedLines
    }

    static func splitMultilineEntries(_ lines: [Line]) -> [Line] {
        lines.flatMap { line -> [Line] in
            let parts = line.text
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard parts.count > 1 else { return [line] }
            return parts.map { Line(time: line.time, text: $0) }
        }
    }

    static func parseOffset(from lrc: String) -> TimeInterval {
        var offsetInMilliseconds = 0

        for rawLine in lrc.components(separatedBy: .newlines) {
            guard let match = rawLine.firstMatch(of: offsetPattern),
                  let value = Int(match.output.1)
            else {
                continue
            }

            offsetInMilliseconds = value
        }

        return TimeInterval(offsetInMilliseconds) / 1000
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

    func activeLineIndex(at currentTime: TimeInterval) -> Int {
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
