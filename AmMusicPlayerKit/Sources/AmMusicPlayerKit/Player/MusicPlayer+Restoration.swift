import AVFoundation
import CoreMedia

public extension MusicPlayer {
    @discardableResult
    func restorePlayback(
        items: [PlayerItem],
        currentIndex: Int,
        shuffled: Bool,
        repeatMode: RepeatMode,
        currentTime: TimeInterval,
        autoPlay: Bool
    ) async -> Bool {
        guard !items.isEmpty else {
            log(.warning, "restorePlayback ignored because items are empty")
            return false
        }

        let clampedCurrentIndex = min(max(currentIndex, 0), items.count - 1)
        log(
            .info,
            "restorePlayback count=\(items.count) currentIndex=\(clampedCurrentIndex) shuffled=\(shuffled) repeatMode=\(repeatMode) currentTime=\(currentTime) autoPlay=\(autoPlay)"
        )

        playbackQueue.restore(
            items: items,
            currentIndex: clampedCurrentIndex,
            shuffled: shuffled,
            repeatMode: repeatMode
        )

        sessionManager.activate()
        remoteCommandManager.unregister()
        remoteCommandManager.register(player: self)
        setupTimeObserver()
        setupItemEndObserver()

        guard let item = playbackQueue.nowPlaying else {
            log(.warning, "restorePlayback failed because no nowPlaying item could be produced")
            return false
        }

        teardownItemObservers()
        currentItem = item
        let avItem = AVPlayerItem(url: item.url)
        engine.replaceCurrentItem(with: avItem)
        observeItemStatus(avItem, for: item)
        observeBuffering(avItem)
        preloadNextItem()

        nowPlayingManager.setTrack(item)
        let snap = queue
        nowPlayingManager.updateQueueInfo(index: snap.history.count, count: snap.totalCount)

        let clampedCurrentTime = max(0, currentTime)
        if clampedCurrentTime > 0 {
            let seekTime = CMTime(seconds: clampedCurrentTime, preferredTimescale: 600)
            _ = await engine.seek(to: seekTime)
        }
        nowPlayingManager.updateElapsedTime(clampedCurrentTime)

        if autoPlay {
            engine.play()
            mediaCenterCoordinator.activateSessionIfPossible()
            setState(.playing)
            nowPlayingManager.updateRate(1.0)
        } else {
            engine.pause()
            setState(.paused)
            nowPlayingManager.updateRate(0.0)
        }

        remoteCommandManager.updateEnabledCommands(queue: snap)
        remoteCommandManager.updateLikeCommand(
            isEnabled: canHandleLikeCommand,
            isActive: currentItemLiked,
            localizedTitle: likeCommandLocalizedTitle,
            localizedShortTitle: likeCommandLocalizedShortTitle
        )
        delegate?.musicPlayer(self, didTransitionTo: item, reason: .natural)
        delegate?.musicPlayer(self, didChangeQueue: snap)
        log(.verbose, "restorePlayback completed \(describe(queue: snap))")
        return true
    }
}
