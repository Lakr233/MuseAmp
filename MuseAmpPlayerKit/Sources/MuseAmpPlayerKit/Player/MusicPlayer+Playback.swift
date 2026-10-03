//
//  MusicPlayer+Playback.swift
//  MuseAmpPlayerKit
//
//  Created by @Lakr233 on 2026/04/11.
//

import AVFoundation
import CoreMedia

public extension MusicPlayer {
    /// Start fresh playback of `items`.
    ///
    /// Pass a non-nil `startIndex` when the user picked a specific track; with
    /// `shuffle: true` that track plays first and the rest are shuffled.
    /// Pass `nil` (the default) when no specific track was chosen; with
    /// `shuffle: true` the whole order — including the first track — is random,
    /// and without shuffle playback starts at the first item.
    func startPlayback(items: [PlayerItem], startIndex: Int? = nil, shuffle: Bool = false) {
        guard !items.isEmpty else {
            log(.warning, "startPlayback ignored because items are empty")
            return
        }

        log(.info, "startPlayback count=\(items.count) startIndex=\(startIndex.map(String.init) ?? "nil") shuffle=\(shuffle)")
        playbackQueue.load(items: items, startIndex: startIndex, shuffle: shuffle)
        log(.verbose, "queue loaded \(describe(queue: queue))")
        preparePlaybackSession()
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
        attachItem(item)
        let snap = startTransition(to: item, reason: reason)
        log(.verbose, "loadAndPlay completed \(describe(queue: snap))")
    }

    internal func continueWithCurrentEngineItem(_ item: PlayerItem, reason: TransitionReason) {
        log(.info, "continueWithCurrentEngineItem item=\(describe(item: item)) reason=\(reason)")
        teardownItemObservers()

        currentItem = item

        if let avItem = engine.currentAVItem {
            observeItemStatus(avItem, for: item)
            observeBuffering(avItem)

            // The preloaded item may have already failed before we started observing.
            if avItem.status == .failed {
                log(.warning, "preloaded item already failed item=\(describe(item: item))")
                handleItemFailure(avItem, for: item)
                return
            }
        }

        engine.clearPreloadedReference()
        let snap = startTransition(to: item, reason: reason)
        log(.verbose, "continueWithCurrentEngineItem completed \(describe(queue: snap))")
    }

    internal func preparePlaybackSession() {
        sessionManager.activate()
        remoteCommandManager.unregister()
        remoteCommandManager.register(player: self)
        setupTimeObserver()
        setupItemEndObserver()
    }

    internal func attachItem(_ item: PlayerItem) {
        teardownItemObservers()
        currentItem = item
        let avItem = AVPlayerItem(url: item.url)
        engine.replaceCurrentItem(with: avItem)
        observeItemStatus(avItem, for: item)
        observeBuffering(avItem)
    }

    internal func startTransition(to item: PlayerItem, reason: TransitionReason) -> QueueSnapshot {
        preloadNextItem()
        engine.play()
        mediaCenterCoordinator.activateSessionIfPossible()
        setState(.playing)

        nowPlayingManager.setTrack(item)
        nowPlayingManager.updateRate(1.0)

        let snap = queue
        nowPlayingManager.updateQueueInfo(
            index: snap.history.count,
            count: snap.totalCount,
        )
        remoteCommandManager.updateEnabledCommands(queue: snap)
        refreshLikeCommand()

        delegate?.musicPlayer(self, didTransitionTo: item, reason: reason)
        delegate?.musicPlayer(self, didChangeQueue: snap)
        return snap
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
