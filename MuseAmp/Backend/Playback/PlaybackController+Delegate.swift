//
//  PlaybackController+Delegate.swift
//  MuseAmp
//
//  Created by @Lakr233 on 2026/04/11.
//

import Combine
import Foundation
import MuseAmpPlayerKit

extension PlaybackController: MusicPlayerDelegate {
    func musicPlayer(_: MuseAmpPlayerKit.MusicPlayer, didChangeState state: PlaybackState) {
        updatePlayHistoryPlayback(isPlaying: state == .playing)
        AppLog.info(
            self,
            "didChangeState previous=\(string(for: latestSnapshot.state)) new=\(string(for: state)) trackID=\(latestSnapshot.currentTrack?.id ?? "nil")",
        )
        refreshSnapshot(persistState: true)
    }

    func musicPlayer(_ player: MuseAmpPlayerKit.MusicPlayer, didTransitionTo item: PlayerItem?, reason: TransitionReason) {
        let fromID = latestSnapshot.currentTrack?.id ?? "nil"
        let toID = item.map { Self.sourceTrackID(for: $0.id) } ?? "nil"
        AppLog.info(
            self,
            "didTransitionTo from=\(fromID) to=\(toID) reason=\(string(for: reason))",
        )
        beginPlayHistoryPlay(for: item)

        if shouldResetCurrentTimeForTrackRepeatTransition(
            player: player,
            item: item,
            reason: reason,
        ) {
            seekState.pendingSeekSnapshotTime = 0
            refreshSnapshot(currentTime: 0, duration: player.duration, persistState: true)
            return
        }

        refreshSnapshot(persistState: true)
    }

    func musicPlayer(_: MuseAmpPlayerKit.MusicPlayer, didChangeQueue snapshot: QueueSnapshot) {
        AppLog.info(
            self,
            "didChangeQueue total=\(snapshot.totalCount) current=\(snapshot.currentIndex.map(String.init) ?? "nil") upcoming=\(snapshot.upcoming.count) shuffled=\(snapshot.shuffled) repeat=\(string(for: snapshot.repeatMode))",
        )
        refreshSnapshot(persistState: true)
    }

    func musicPlayer(_: MuseAmpPlayerKit.MusicPlayer, didUpdateTime currentTime: TimeInterval, duration: TimeInterval) {
        updatePlayHistoryTime(duration: duration)
        guard !isUIPublishingSuspended else { return }
        latestSnapshot = latestSnapshot.withTime(currentTime, duration: duration)
        playbackTimeSubject.send((currentTime, duration))
    }

    func musicPlayer(_: MuseAmpPlayerKit.MusicPlayer, didFailItem item: PlayerItem, error: any Error) {
        AppLog.error(self, "didFailItem trackID=\(Self.sourceTrackID(for: item.id)) error=\(error)")
        refreshSnapshot(persistState: true)
    }

    func musicPlayerDidReachEndOfQueue(_: MuseAmpPlayerKit.MusicPlayer) {
        AppLog.info(
            self,
            "didReachEndOfQueue total=\(latestSnapshot.queue.count) repeat=\(string(for: latestSnapshot.repeatMode))",
        )
    }
}
