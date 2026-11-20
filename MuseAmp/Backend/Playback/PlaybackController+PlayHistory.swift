//
//  PlaybackController+PlayHistory.swift
//  MuseAmp
//
//  Created by @Lakr233 on 2026/11/20.
//

import Foundation
import MuseAmpPlayerKit

extension PlaybackController {
    private var playHistoryNow: TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }

    func beginPlayHistoryPlay(for item: PlayerItem?) {
        guard playHistoryStore != nil else {
            return
        }
        let track = item.flatMap { queueState.trackLookup[$0.id] }
        let trackID = item.map { track?.id ?? Self.sourceTrackID(for: $0.id) }
        let finished = playHistoryTracker.begin(
            trackID: trackID,
            albumID: track?.albumID,
            duration: track?.durationInSeconds ?? item?.durationInSeconds ?? 0,
            isPlaying: player.state == .playing,
            now: playHistoryNow,
        )
        recordPlayHistory(finished)
    }

    func updatePlayHistoryPlayback(isPlaying: Bool) {
        guard playHistoryStore != nil else {
            return
        }
        let now = playHistoryNow
        recordPlayHistory(playHistoryTracker.takeQualifiedPlay(now: now))
        playHistoryTracker.setPlaying(isPlaying, now: now)
    }

    func updatePlayHistoryTime(duration: TimeInterval) {
        guard playHistoryStore != nil else {
            return
        }
        playHistoryTracker.updateDuration(duration)
        recordPlayHistory(playHistoryTracker.takeQualifiedPlay(now: playHistoryNow))
    }

    private func recordPlayHistory(_ play: PlayHistoryTracker.Play?) {
        guard let play, let playHistoryStore else {
            return
        }
        playHistoryStore.recordPlay(trackID: play.trackID, albumID: play.albumID)
    }
}
