//
//  PlayHistoryTracker.swift
//  MuseAmp
//
//  Created by @Lakr233 on 2026/11/20.
//

import Foundation

/// Measures how long the current play has actually been heard, so seeking or
/// skipping ahead does not count as listening. One play is reported at most
/// once; starting the song again begins a new play.
nonisolated struct PlayHistoryTracker {
    nonisolated struct Play: Equatable {
        let trackID: String
        let albumID: String?
        var duration: TimeInterval
        var listenedSeconds: TimeInterval = 0
        var playingSince: TimeInterval?
        var didRecord = false
    }

    private(set) var current: Play?

    /// Ends the current play (returning it when it qualified and was not yet
    /// reported) and starts tracking a new one.
    mutating func begin(
        trackID: String?,
        albumID: String?,
        duration: TimeInterval,
        isPlaying: Bool,
        now: TimeInterval,
    ) -> Play? {
        let finished = takeQualifiedPlay(now: now)
        guard let trackID else {
            current = nil
            return finished
        }
        current = Play(
            trackID: trackID,
            albumID: albumID,
            duration: duration,
            playingSince: isPlaying ? now : nil,
        )
        return finished
    }

    mutating func setPlaying(_ isPlaying: Bool, now: TimeInterval) {
        guard var play = current else {
            return
        }
        accumulate(&play, now: now)
        play.playingSince = isPlaying ? now : nil
        current = play
    }

    mutating func updateDuration(_ duration: TimeInterval) {
        guard duration.isFinite, duration > 0 else {
            return
        }
        current?.duration = duration
    }

    /// Returns the current play the first time it qualifies.
    mutating func takeQualifiedPlay(now: TimeInterval) -> Play? {
        guard var play = current else {
            return nil
        }
        accumulate(&play, now: now)
        if play.playingSince != nil {
            play.playingSince = now
        }
        defer { current = play }
        guard !play.didRecord,
              PlayHistoryStore.countsAsPlayed(listenedSeconds: play.listenedSeconds, duration: play.duration)
        else {
            return nil
        }
        play.didRecord = true
        return play
    }

    private func accumulate(_ play: inout Play, now: TimeInterval) {
        guard let since = play.playingSince, now > since else {
            return
        }
        play.listenedSeconds += now - since
        play.playingSince = now
    }
}
