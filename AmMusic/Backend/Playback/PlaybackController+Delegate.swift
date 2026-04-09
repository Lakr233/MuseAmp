import AmMusicPlayerKit
import Foundation

extension PlaybackController: MusicPlayerDelegate {
    func musicPlayer(_: AmMusicPlayerKit.MusicPlayer, didChangeState state: PlaybackState) {
        AppLog.info(
            self,
            "didChangeState previous=\(string(for: latestSnapshot.state)) new=\(string(for: state)) trackID=\(latestSnapshot.currentTrack?.id ?? "nil")"
        )
        refreshSnapshot(persistState: true)
    }

    func musicPlayer(_ player: AmMusicPlayerKit.MusicPlayer, didTransitionTo item: PlayerItem?, reason: TransitionReason) {
        let fromID = latestSnapshot.currentTrack?.id ?? "nil"
        let toID = item.map { Self.sourceTrackID(for: $0.id) } ?? "nil"
        AppLog.info(
            self,
            "didTransitionTo from=\(fromID) to=\(toID) reason=\(string(for: reason))"
        )

        if shouldResetCurrentTimeForTrackRepeatTransition(
            player: player,
            item: item,
            reason: reason
        ) {
            timeUpdateState.pendingSeekSnapshotTime = 0
            beginPostSeekTimeUpdateSuppression()
            refreshSnapshot(currentTime: 0, duration: player.duration, persistState: true)
            return
        }

        refreshSnapshot(persistState: true)
    }

    func musicPlayer(_: AmMusicPlayerKit.MusicPlayer, didChangeQueue snapshot: QueueSnapshot) {
        AppLog.info(
            self,
            "didChangeQueue total=\(snapshot.totalCount) current=\(snapshot.currentIndex.map(String.init) ?? "nil") upcoming=\(snapshot.upcoming.count) shuffled=\(snapshot.shuffled) repeat=\(string(for: snapshot.repeatMode))"
        )
        refreshSnapshot(persistState: true)
    }

    func musicPlayer(_: AmMusicPlayerKit.MusicPlayer, didUpdateTime currentTime: TimeInterval, duration: TimeInterval) {
        guard !isUIPublishingSuspended else {
            return
        }
        guard shouldApplyTimeUpdate() else {
            return
        }
        timeUpdateState.pendingSeekSnapshotTime = nil
        refreshSnapshot(currentTime: currentTime, duration: duration)
    }

    func musicPlayer(_: AmMusicPlayerKit.MusicPlayer, didFailItem item: PlayerItem, error: any Error) {
        AppLog.error(self, "didFailItem trackID=\(Self.sourceTrackID(for: item.id)) error=\(error)")
        refreshSnapshot(persistState: true)
    }

    func musicPlayerDidReachEndOfQueue(_: AmMusicPlayerKit.MusicPlayer) {
        AppLog.info(
            self,
            "didReachEndOfQueue total=\(latestSnapshot.queue.count) repeat=\(string(for: latestSnapshot.repeatMode))"
        )
    }
}
