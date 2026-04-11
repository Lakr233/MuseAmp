//
//  AudioPlaybackEngine.swift
//  AmMusicPlayerKit
//
//  Created by @Lakr233 on 2026/04/11.
//

import AVFoundation

@MainActor
protocol AudioPlaybackEngine: AnyObject {
    var rate: Float { get }
    var currentAVItem: AVPlayerItem? { get }
    var mediaCenterPlayer: AVPlayer? { get }

    func replaceCurrentItem(with item: AVPlayerItem?)
    func play()
    func pause()
    func seek(to time: CMTime) async -> Bool
    func currentTime() -> CMTime

    func addPeriodicTimeObserver(
        forInterval interval: CMTime,
        queue: DispatchQueue?,
        using block: @escaping @Sendable (CMTime) -> Void,
    ) -> Any

    func removeTimeObserver(_ observer: Any)

    func preloadNextItem(_ item: AVPlayerItem?)

    /// Returns `true` when `AVQueuePlayer` has auto-advanced to the preloaded item
    /// (i.e. the preloaded item is now `currentItem`).
    func hasAdvancedToPreloadedItem() -> Bool

    /// Tells the underlying queue player to advance to the preloaded next item
    /// without tearing down the queue. Returns `true` on success.
    func advanceToPreloadedItem() -> Bool

    /// Clears the internal preloaded-item reference without removing it from the player queue.
    func clearPreloadedReference()
}
