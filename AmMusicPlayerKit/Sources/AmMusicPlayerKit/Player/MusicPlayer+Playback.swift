import AVFoundation
import CoreMedia

public extension MusicPlayer {
    func startPlayback(items: [PlayerItem], startIndex: Int = 0, shuffle: Bool = false) {
        guard !items.isEmpty else {
            log(.warning, "startPlayback ignored because items are empty")
            return
        }

        log(.info, "startPlayback count=\(items.count) startIndex=\(startIndex) shuffle=\(shuffle)")
        playbackQueue.load(items: items, startIndex: startIndex, shuffle: shuffle)
        log(.verbose, "queue loaded \(describe(queue: queue))")
        sessionManager.activate()
        remoteCommandManager.unregister()
        remoteCommandManager.register(player: self)
        setupTimeObserver()
        setupItemEndObserver()
        loadAndPlay(playbackQueue.nowPlaying, reason: .natural)
    }

    func play() {
        guard state != .playing else {
            log(.verbose, "play ignored because state is already playing")
            return
        }

        log(.info, "play requested current=\(describe(item: currentItem))")
        engine.play()
        mediaCenterCoordinator.activateSessionIfPossible()
        setState(.playing)
        nowPlayingManager.updateRate(1.0)
    }

    func pause() {
        guard state == .playing || state == .buffering else {
            log(.verbose, "pause ignored because state=\(state)")
            return
        }

        log(.info, "pause requested current=\(describe(item: currentItem))")
        engine.pause()
        setState(.paused)
        nowPlayingManager.updateRate(0.0)
        nowPlayingManager.updateElapsedTime(currentTime)
    }

    func togglePlayPause() {
        log(.verbose, "togglePlayPause currentState=\(state)")
        if state == .playing {
            pause()
        } else {
            play()
        }
    }

    func stop() {
        log(.info, "stop requested current=\(describe(item: currentItem)) queue=\(describe(queue: queue))")
        teardownObservers()
        engine.pause()
        engine.replaceCurrentItem(with: nil)
        playbackQueue.clear()
        setState(.idle)
        currentItem = nil
        currentItemLiked = false
        nowPlayingManager.clear()
        remoteCommandManager.unregister()
        sessionManager.deactivate()
        // Session observers stay alive for the player's lifetime
        delegate?.musicPlayer(self, didTransitionTo: nil, reason: .natural)
        delegate?.musicPlayer(self, didChangeQueue: queue)
        log(.info, "stop completed")
    }

    func seek(to seconds: TimeInterval) async {
        log(.info, "seek requested seconds=\(seconds) current=\(describe(item: currentItem))")
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        let finished = await engine.seek(to: time)
        log(finished ? .verbose : .warning, "seek completed finished=\(finished) seconds=\(seconds)")
        nowPlayingManager.updateElapsedTime(seconds)
    }

    // MARK: - Internal

    internal func loadAndPlay(_ item: PlayerItem?, reason: TransitionReason) {
        guard let item else {
            log(.info, "loadAndPlay reached end of queue reason=\(reason)")
            delegate?.musicPlayerDidReachEndOfQueue(self)
            stop()
            return
        }

        log(.info, "loadAndPlay item=\(describe(item: item)) reason=\(reason)")
        teardownItemObservers()

        currentItem = item
        let avItem = AVPlayerItem(url: item.url)
        engine.replaceCurrentItem(with: avItem)
        observeItemStatus(avItem, for: item)
        observeBuffering(avItem)
        preloadNextItem()
        engine.play()
        mediaCenterCoordinator.activateSessionIfPossible()
        setState(.playing)

        nowPlayingManager.setTrack(item)
        nowPlayingManager.updateRate(1.0)

        let snap = queue
        nowPlayingManager.updateQueueInfo(
            index: snap.history.count,
            count: snap.totalCount
        )
        remoteCommandManager.updateEnabledCommands(queue: snap)
        remoteCommandManager.updateLikeCommand(
            isEnabled: canHandleLikeCommand,
            isActive: currentItemLiked,
            localizedTitle: likeCommandLocalizedTitle,
            localizedShortTitle: likeCommandLocalizedShortTitle
        )

        delegate?.musicPlayer(self, didTransitionTo: item, reason: reason)
        delegate?.musicPlayer(self, didChangeQueue: snap)
        log(.verbose, "loadAndPlay completed \(describe(queue: snap))")
    }

    internal func preloadNextItem() {
        guard repeatMode != .track else {
            log(.verbose, "clearing preloaded next item because repeatMode=track")
            engine.preloadNextItem(nil)
            return
        }

        let upcomingItems = playbackQueue.snapshot().upcoming
        if let next = upcomingItems.first {
            log(.verbose, "preloading next item=\(describe(item: next))")
            engine.preloadNextItem(AVPlayerItem(url: next.url))
        } else {
            log(.verbose, "clearing preloaded next item")
            engine.preloadNextItem(nil)
        }
    }
}
