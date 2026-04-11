//
//  AVPlayerEngine.swift
//  AmMusicPlayerKit
//
//  Created by @Lakr233 on 2026/04/11.
//

import AVFoundation

@MainActor
final class AVPlayerEngine: AudioPlaybackEngine {
    private let player = AVQueuePlayer()
    private let logger: any MusicPlayerLogger
    private var preloadedItem: AVPlayerItem?

    init(logger: any MusicPlayerLogger = NoopMusicPlayerLogger()) {
        self.logger = logger
        #if os(iOS) || os(tvOS)
            player.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
            player.usesExternalPlaybackWhileExternalScreenIsActive = true
        #endif
        player.allowsExternalPlayback = false
        #if os(iOS) || os(tvOS)
            let externalScreenPlayback = player.usesExternalPlaybackWhileExternalScreenIsActive
        #else
            let externalScreenPlayback = false
        #endif
        log(
            .info,
            """
            configured player allowsExternalPlayback=\(player.allowsExternalPlayback) \
            usesExternalPlaybackWhileExternalScreenIsActive=\(externalScreenPlayback)
            """,
        )
    }

    var routePlayer: AVPlayer {
        player
    }

    var rate: Float {
        player.rate
    }

    var currentAVItem: AVPlayerItem? {
        player.currentItem
    }

    var mediaCenterPlayer: AVPlayer? {
        player
    }

    func replaceCurrentItem(with item: AVPlayerItem?) {
        log(.verbose, "replaceCurrentItem hasItem=\(item != nil)")
        player.removeAllItems()
        preloadedItem = nil

        if let item {
            player.insert(item, after: nil)
        }
    }

    func play() {
        log(.verbose, "play")
        player.play()
    }

    func pause() {
        log(.verbose, "pause")
        player.pause()
    }

    func seek(to time: CMTime) async -> Bool {
        log(.verbose, "seek seconds=\(time.seconds)")
        let logger = logger
        return await withCheckedContinuation { continuation in
            player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { finished in
                logger.log(
                    level: finished ? .verbose : .warning,
                    component: "AVPlayerEngine",
                    message: "seek completed finished=\(finished) seconds=\(time.seconds)",
                )
                continuation.resume(returning: finished)
            }
        }
    }

    func currentTime() -> CMTime {
        player.currentTime()
    }

    func addPeriodicTimeObserver(
        forInterval interval: CMTime,
        queue: DispatchQueue?,
        using block: @escaping @Sendable (CMTime) -> Void,
    ) -> Any {
        log(.verbose, "addPeriodicTimeObserver interval=\(interval.seconds)")
        return player.addPeriodicTimeObserver(forInterval: interval, queue: queue, using: block)
    }

    func removeTimeObserver(_ observer: Any) {
        log(.verbose, "removeTimeObserver")
        player.removeTimeObserver(observer)
    }

    func preloadNextItem(_ item: AVPlayerItem?) {
        log(.verbose, "preloadNextItem hasItem=\(item != nil)")
        // Remove the old preloaded item if it's still in the queue,
        // but never remove the currently playing item (can happen if
        // AVQueuePlayer auto-advanced before the reference was cleared).
        if let old = preloadedItem, player.currentItem !== old, player.items().contains(old) {
            player.remove(old)
        }
        preloadedItem = item

        // Insert next item after current for gapless playback
        if let item {
            player.insert(item, after: player.currentItem)
        }
    }

    func hasAdvancedToPreloadedItem() -> Bool {
        guard let preloaded = preloadedItem else { return false }
        return player.currentItem === preloaded
    }

    func advanceToPreloadedItem() -> Bool {
        guard let preloaded = preloadedItem else { return false }

        if player.currentItem === preloaded {
            // AVQueuePlayer already auto-advanced; just clear the reference.
            log(.verbose, "advanceToPreloadedItem (already current)")
            preloadedItem = nil
            return true
        }

        guard player.items().contains(preloaded) else { return false }
        log(.verbose, "advanceToPreloadedItem")
        player.advanceToNextItem()
        preloadedItem = nil
        return true
    }

    func clearPreloadedReference() {
        preloadedItem = nil
    }

    private func log(_ level: MusicPlayerLogLevel, _ message: String) {
        logger.log(level: level, component: "AVPlayerEngine", message: message)
    }
}
