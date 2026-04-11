//
//  PlaybackTimeFormatting.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import Foundation

func formattedPlaybackTime(_ seconds: TimeInterval) -> String {
    let totalSeconds = max(Int(seconds.rounded(.down)), 0)
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let secs = totalSeconds % 60

    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, secs)
    }
    return String(format: "%d:%02d", minutes, secs)
}

func formattedDuration(millis: Int) -> String {
    String(format: "%d:%02d", millis / 1000 / 60, millis / 1000 % 60)
}

func formattedDuration(seconds: Int) -> String {
    String(format: "%d:%02d", seconds / 60, seconds % 60)
}
