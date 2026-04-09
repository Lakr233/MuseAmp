import AmMusicPlayerKit
import AVFoundation
import Foundation

// MARK: - Snapshot Management

extension PlaybackController {
    func refreshSnapshot(
        currentTime: TimeInterval? = nil,
        duration: TimeInterval? = nil,
        persistState: Bool = false
    ) {
        let queue = player.queue
        if queue.totalCount == 0 {
            queueState.reset()
            timeUpdateState.pendingSeekSnapshotTime = nil
        }

        if canPerformLightweightSnapshotRefresh(
            queue: queue,
            currentTime: currentTime,
            duration: duration
        ) {
            publishLightweightSnapshot(
                currentTime: currentTime,
                duration: duration,
                persistState: persistState
            )
            return
        }

        AppLog.verbose(
            self,
            "refreshSnapshot full state=\(string(for: player.state)) queueTotal=\(queue.totalCount) persist=\(persistState)"
        )
        let orderedQueue = queue.orderedItems.compactMap(track(for:))
        let playerIndex = queue.currentIndex.flatMap { index in
            orderedQueue.indices.contains(index) ? index : nil
        }
        let currentTrack = playerIndex.flatMap { orderedQueue[$0] }
        if currentTrack?.id != latestSnapshot.currentTrack?.id {
            timeUpdateState.pendingSeekSnapshotTime = nil
        }
        let resolvedCurrentTime = resolvedSnapshotCurrentTime(
            explicitCurrentTime: currentTime,
            state: player.state,
            currentTrack: currentTrack
        )
        let nextSnapshot = PlaybackSnapshot(
            state: player.state,
            queue: orderedQueue,
            playerIndex: playerIndex,
            currentTime: resolvedCurrentTime,
            duration: duration ?? player.duration,
            repeatMode: player.repeatMode,
            shuffled: queue.shuffled,
            source: queueState.currentSource,
            isCurrentTrackLiked: currentTrack.map { playlistStore.isLiked(trackID: $0.id) } ?? false,
            outputDevice: currentOutputDevice()
        )
        latestSnapshot = nextSnapshot
        if !isUIPublishingSuspended {
            snapshot = nextSnapshot
        }
        updatePlaybackStatusLogTimer()
        player.setCurrentItemLiked(nextSnapshot.isCurrentTrackLiked)
        if persistState {
            persistPlaybackState()
        }
    }

    func canPerformLightweightSnapshotRefresh(
        queue: QueueSnapshot,
        currentTime: TimeInterval?,
        duration: TimeInterval?
    ) -> Bool {
        guard currentTime != nil || duration != nil else {
            return false
        }
        guard queue.totalCount > 0,
              latestSnapshot.queue.count == queue.totalCount,
              latestSnapshot.playerIndex == queue.currentIndex,
              latestSnapshot.state == player.state,
              latestSnapshot.repeatMode == player.repeatMode,
              latestSnapshot.shuffled == queue.shuffled,
              track(for: player.currentItem) == latestSnapshot.currentTrack
        else {
            return false
        }
        return true
    }

    func publishLightweightSnapshot(
        currentTime: TimeInterval?,
        duration: TimeInterval?,
        persistState: Bool
    ) {
        let nextSnapshot = PlaybackSnapshot(
            state: latestSnapshot.state,
            queue: latestSnapshot.queue,
            playerIndex: latestSnapshot.playerIndex,
            currentTime: resolvedSnapshotCurrentTime(
                explicitCurrentTime: currentTime,
                state: latestSnapshot.state,
                currentTrack: latestSnapshot.currentTrack
            ),
            duration: duration ?? player.duration,
            repeatMode: latestSnapshot.repeatMode,
            shuffled: latestSnapshot.shuffled,
            source: latestSnapshot.source,
            isCurrentTrackLiked: latestSnapshot.isCurrentTrackLiked,
            outputDevice: latestSnapshot.outputDevice
        )
        latestSnapshot = nextSnapshot
        if !isUIPublishingSuspended {
            snapshot = nextSnapshot
        }
        updatePlaybackStatusLogTimer()
        player.setCurrentItemLiked(nextSnapshot.isCurrentTrackLiked)
        if persistState {
            persistPlaybackState()
        }
    }

    func handleRouteChange(reason: AVAudioSession.RouteChangeReason?) {
        if let reason {
            AppLog.info(self, "Audio route changed reason=\(String(describing: reason))")
        } else {
            AppLog.info(self, "Audio route changed")
        }
        refreshSnapshot(persistState: true)
    }

    func beginPostSeekTimeUpdateSuppression() {
        let deadline = Date().addingTimeInterval(Self.postSeekTimeUpdateSuppressionInterval)
        timeUpdateState.suppressionDeadline = deadline
        timeUpdateState.flushTask?.cancel()
        timeUpdateState.flushTask = Task { [weak self] in
            guard let self else { return }
            let nanoseconds = UInt64(Self.postSeekTimeUpdateSuppressionInterval * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let suppressionDeadline = self.timeUpdateState.suppressionDeadline,
                      Date() >= suppressionDeadline
                else {
                    return
                }
                self.timeUpdateState.suppressionDeadline = nil
                if self.shouldKeepPendingSeekSnapshotTime(for: self.player.state) {
                    self.refreshSnapshot(
                        currentTime: self.timeUpdateState.pendingSeekSnapshotTime,
                        duration: self.player.duration
                    )
                    return
                }

                self.timeUpdateState.pendingSeekSnapshotTime = nil
                self.refreshSnapshot(currentTime: self.player.currentTime, duration: self.player.duration)
            }
        }
    }

    func updatePlaybackStatusLogTimer() {
        guard shouldEmitPeriodicPlaybackStatusLog else {
            playbackStatusLogTimer?.invalidate()
            playbackStatusLogTimer = nil
            return
        }

        guard playbackStatusLogTimer == nil else {
            return
        }

        let timer = Timer.scheduledTimer(
            withTimeInterval: Self.periodicPlaybackStatusLogInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.logPeriodicPlaybackStatus()
            }
        }
        timer.tolerance = 1
        playbackStatusLogTimer = timer
    }

    var shouldEmitPeriodicPlaybackStatusLog: Bool {
        !isUIPublishingSuspended && latestSnapshot.state == .playing && latestSnapshot.currentTrack != nil
    }

    func logPeriodicPlaybackStatus() {
        guard shouldEmitPeriodicPlaybackStatusLog else {
            playbackStatusLogTimer?.invalidate()
            playbackStatusLogTimer = nil
            return
        }

        let trackID = latestSnapshot.currentTrack?.id ?? "nil"
        let title = latestSnapshot.currentTrack?.title ?? "nil"
        let artist = latestSnapshot.currentTrack?.artistName ?? "nil"
        let output = latestSnapshot.outputDevice.map { "\($0.name) [\(string(for: $0.kind))]" } ?? "nil"

        AppLog.info(
            self,
            "Periodic playback status state=\(string(for: latestSnapshot.state)) trackID=\(trackID) title=\"\(sanitizedLogText(title))\" artist=\"\(sanitizedLogText(artist))\" progress=\(formattedPlaybackTime(latestSnapshot.currentTime))/\(formattedPlaybackTime(latestSnapshot.duration)) history=\(latestSnapshot.history.count) upcoming=\(latestSnapshot.upcoming.count) shuffled=\(latestSnapshot.shuffled) repeat=\(string(for: latestSnapshot.repeatMode)) output=\(output)"
        )
    }

    func shouldApplyTimeUpdate(at date: Date = Date()) -> Bool {
        guard let deadline = timeUpdateState.suppressionDeadline else {
            return true
        }
        guard date < deadline else {
            timeUpdateState.suppressionDeadline = nil
            return true
        }
        return false
    }

    func shouldResetCurrentTimeForTrackRepeatTransition(
        player: AmMusicPlayerKit.MusicPlayer,
        item: PlayerItem?,
        reason: TransitionReason
    ) -> Bool {
        guard case .natural = reason,
              player.repeatMode == .track,
              let item,
              let currentTrack = latestSnapshot.currentTrack
        else {
            return false
        }

        return Self.sourceTrackID(for: item.id) == currentTrack.id
    }

    func resolvedSnapshotCurrentTime(
        explicitCurrentTime: TimeInterval?,
        state: PlaybackState,
        currentTrack: PlaybackTrack?
    ) -> TimeInterval {
        if let explicitCurrentTime {
            return explicitCurrentTime
        }

        guard currentTrack != nil,
              shouldKeepPendingSeekSnapshotTime(for: state),
              let pendingSeekSnapshotTime = timeUpdateState.pendingSeekSnapshotTime
        else {
            return player.currentTime
        }

        return pendingSeekSnapshotTime
    }

    func shouldKeepPendingSeekSnapshotTime(for state: PlaybackState) -> Bool {
        switch state {
        case .idle, .paused, .error:
            true
        case .playing, .buffering:
            false
        }
    }

    func currentOutputDevice() -> PlaybackOutputDevice? {
        PlaybackOutputDevice(currentRoute: AVAudioSession.sharedInstance().currentRoute)
    }

    func string(for state: PlaybackState) -> String {
        switch state {
        case .idle:
            "idle"
        case .playing:
            "playing"
        case .paused:
            "paused"
        case .buffering:
            "buffering"
        case let .error(message):
            "error(\(sanitizedLogText(message)))"
        }
    }

    func string(for repeatMode: RepeatMode) -> String {
        switch repeatMode {
        case .off:
            "off"
        case .track:
            "track"
        case .queue:
            "queue"
        }
    }

    func string(for outputKind: PlaybackOutputDevice.Kind) -> String {
        switch outputKind {
        case .builtInSpeaker:
            "builtInSpeaker"
        case .builtInReceiver:
            "builtInReceiver"
        case .wiredHeadphones:
            "wiredHeadphones"
        case .bluetooth:
            "bluetooth"
        case .airPlay:
            "airPlay"
        case .carAudio:
            "carAudio"
        case .television:
            "television"
        case .external:
            "external"
        case .unknown:
            "unknown"
        }
    }

    func string(for reason: TransitionReason) -> String {
        switch reason {
        case .natural:
            "natural"
        case .userNext:
            "userNext"
        case .userPrevious:
            "userPrevious"
        case let .userSkip(toIndex):
            "userSkip(\(toIndex))"
        case .itemFailed:
            "itemFailed"
        }
    }
}
