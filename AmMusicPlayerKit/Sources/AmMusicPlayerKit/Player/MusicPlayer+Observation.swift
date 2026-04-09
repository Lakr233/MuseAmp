import AVFoundation
import CoreMedia
import Foundation

extension MusicPlayer {
    func setupTimeObserver() {
        guard timeObserver == nil else {
            log(.verbose, "setupTimeObserver ignored because observer already exists")
            return
        }
        guard !isPeriodicTimeObserverSuspended else {
            log(.verbose, "setupTimeObserver deferred because periodic updates are suspended")
            return
        }
        let interval = CMTime(seconds: timeUpdateInterval, preferredTimescale: 600)
        log(.verbose, "setting up time observer interval=\(timeUpdateInterval)")
        timeObserver = engine.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard time.isValid, !time.isIndefinite else { return }
                let ct = time.seconds
                let dur = duration
                delegate?.musicPlayer(self, didUpdateTime: ct, duration: dur)
                nowPlayingManager.updateElapsedTime(ct)
            }
        }
    }

    func setupItemEndObserver() {
        guard itemEndObserver == nil else {
            log(.verbose, "setupItemEndObserver ignored because observer already exists")
            return
        }
        log(.verbose, "setting up item end observer")
        itemEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleItemEnd()
            }
        }
    }

    func handleItemEnd() {
        log(.info, "handleItemEnd repeatMode=\(repeatMode) current=\(describe(item: currentItem))")
        switch repeatMode {
        case .track:
            guard let currentItem else {
                log(.warning, "repeat-track end ignored because current item is missing")
                return
            }
            log(.verbose, "restarting current track after end item=\(describe(item: currentItem))")
            loadAndPlay(currentItem, reason: .natural)
        case .queue, .off:
            if let next = playbackQueue.advance() {
                log(.verbose, "advancing to next item after end item=\(describe(item: next))")
                loadAndPlay(next, reason: .natural)
            } else {
                log(.info, "handleItemEnd reached end of queue")
                delegate?.musicPlayerDidReachEndOfQueue(self)
                if repeatMode == .off {
                    stop()
                }
            }
        }
    }

    func observeItemStatus(_ avItem: AVPlayerItem, for playerItem: PlayerItem) {
        log(.verbose, "observing status item=\(describe(item: playerItem))")
        statusObservation = avItem.observe(\.status, options: [.new]) {
            [weak self, playerItem] item, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if item.status == .failed {
                    let error = item.error ?? NSError(
                        domain: "AmMusicPlayerKit",
                        code: -1,
                        userInfo: [
                            NSLocalizedDescriptionKey: String(
                                localized: "Unknown playback error",
                                bundle: .module
                            ),
                        ]
                    )
                    log(.error, "player item failed item=\(describe(item: playerItem)) error=\(error.localizedDescription)")
                    delegate?.musicPlayer(self, didFailItem: playerItem, error: error)
                    // Advance directly with .itemFailed reason instead of going through next()
                    if let nextItem = playbackQueue.advance() {
                        log(.warning, "advancing after failed item next=\(describe(item: nextItem))")
                        loadAndPlay(nextItem, reason: .itemFailed)
                    } else {
                        log(.warning, "failed item ended queue playback")
                        delegate?.musicPlayerDidReachEndOfQueue(self)
                        stop()
                    }
                }
            }
        }
    }

    func observeBuffering(_ avItem: AVPlayerItem) {
        log(.verbose, "observing buffering item=\(describe(item: currentItem))")
        bufferEmptyObservation = avItem.observe(\.isPlaybackBufferEmpty, options: [.new]) {
            [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if item.isPlaybackBufferEmpty, state == .playing {
                    log(.warning, "playback buffer empty")
                    setState(.buffering)
                }
            }
        }

        likelyToKeepUpObservation = avItem.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) {
            [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if item.isPlaybackLikelyToKeepUp, state == .buffering {
                    log(.info, "buffer recovered and playback can continue")
                    setState(.playing)
                }
            }
        }
    }

    func teardownItemObservers() {
        log(.verbose, "tearing down item observers")
        statusObservation?.invalidate()
        statusObservation = nil
        bufferEmptyObservation?.invalidate()
        bufferEmptyObservation = nil
        likelyToKeepUpObservation?.invalidate()
        likelyToKeepUpObservation = nil
    }

    func teardownObservers() {
        if let obs = timeObserver {
            log(.verbose, "removing time observer")
            engine.removeTimeObserver(obs)
            timeObserver = nil
        }
        if let obs = itemEndObserver {
            log(.verbose, "removing item end observer")
            NotificationCenter.default.removeObserver(obs)
            itemEndObserver = nil
        }
        teardownItemObservers()
    }
}
