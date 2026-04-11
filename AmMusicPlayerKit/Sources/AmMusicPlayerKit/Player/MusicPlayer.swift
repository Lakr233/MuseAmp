//
//  MusicPlayer.swift
//  AmMusicPlayerKit
//
//  Created by @Lakr233 on 2026/04/11.
//

import AVFoundation
import Foundation
import MediaPlayer

@MainActor
public protocol MusicPlayerDelegate: AnyObject {
    func musicPlayer(_ player: MusicPlayer, didChangeState state: PlaybackState)
    func musicPlayer(_ player: MusicPlayer, didTransitionTo item: PlayerItem?, reason: TransitionReason)
    func musicPlayer(_ player: MusicPlayer, didChangeQueue snapshot: QueueSnapshot)
    func musicPlayer(_ player: MusicPlayer, didUpdateTime currentTime: TimeInterval, duration: TimeInterval)
    func musicPlayer(_ player: MusicPlayer, didFailItem item: PlayerItem, error: any Error)
    func musicPlayerDidReachEndOfQueue(_ player: MusicPlayer)
}

public extension MusicPlayerDelegate {
    func musicPlayer(_: MusicPlayer, didChangeState _: PlaybackState) {}
    func musicPlayer(_: MusicPlayer, didTransitionTo _: PlayerItem?, reason _: TransitionReason) {}
    func musicPlayer(_: MusicPlayer, didChangeQueue _: QueueSnapshot) {}
    func musicPlayer(_: MusicPlayer, didUpdateTime _: TimeInterval, duration _: TimeInterval) {}
    func musicPlayer(_: MusicPlayer, didFailItem _: PlayerItem, error _: any Error) {}
    func musicPlayerDidReachEndOfQueue(_: MusicPlayer) {}
}

@MainActor
public final class MusicPlayer {
    // MARK: - Public Properties

    public weak var delegate: (any MusicPlayerDelegate)?

    public private(set) var state: PlaybackState = .idle

    public internal(set) var currentItem: PlayerItem?

    public var currentTime: TimeInterval {
        let time = engine.currentTime()
        guard time.isValid, !time.isIndefinite else { return 0 }
        return time.seconds
    }

    public var duration: TimeInterval {
        guard let item = engine.currentAVItem else { return 0 }
        let dur = item.duration
        guard dur.isValid, !dur.isIndefinite else { return 0 }
        return dur.seconds
    }

    public var queue: QueueSnapshot {
        playbackQueue.snapshot()
    }

    public var shuffled: Bool {
        get { playbackQueue.shuffled }
        set {
            playbackQueue.setShuffle(newValue)
            preloadNextItem()
            delegate?.musicPlayer(self, didChangeQueue: queue)
        }
    }

    public var repeatMode: RepeatMode {
        get { playbackQueue.repeatMode }
        set {
            playbackQueue.setRepeatMode(newValue)
            preloadNextItem()
            remoteCommandManager.updateEnabledCommands(queue: queue)
        }
    }

    public var timeUpdateInterval: TimeInterval = 0.25

    var isPeriodicTimeObserverSuspended = false

    // MARK: - Internal

    var playbackQueue = PlaybackQueue()
    let logger: any MusicPlayerLogger
    let engine: any AudioPlaybackEngine
    let sessionManager: AudioSessionManager
    let mediaCenterCoordinator: MediaCenterCoordinator
    let nowPlayingManager: NowPlayingInfoManager
    let remoteCommandManager: RemoteCommandManager

    var timeObserver: Any?
    var itemEndObserver: (any NSObjectProtocol)?
    var statusObservation: NSKeyValueObservation?
    var bufferEmptyObservation: NSKeyValueObservation?
    var likelyToKeepUpObservation: NSKeyValueObservation?
    var likeCommandHandler: (() -> Bool)?
    var likeCommandLocalizedTitle = String(localized: "Like", bundle: .module)
    var likeCommandLocalizedShortTitle: String?
    var currentItemLiked = false

    // MARK: - Init

    public convenience init(logger: any MusicPlayerLogger = NoopMusicPlayerLogger()) {
        self.init(engine: AVPlayerEngine(logger: logger), logger: logger)
    }

    init(engine: any AudioPlaybackEngine, logger: any MusicPlayerLogger = NoopMusicPlayerLogger()) {
        let mediaCenterCoordinator = MediaCenterCoordinator(engine: engine, logger: logger)
        self.logger = logger
        self.engine = engine
        sessionManager = AudioSessionManager(logger: logger)
        self.mediaCenterCoordinator = mediaCenterCoordinator
        nowPlayingManager = NowPlayingInfoManager(publisher: mediaCenterCoordinator)
        remoteCommandManager = RemoteCommandManager(provider: mediaCenterCoordinator)
        commonInit()
    }

    private func commonInit() {
        log(.info, "initialized")
        sessionManager.configure(
            onInterruptionBegan: { [weak self] in
                Task { @MainActor in
                    self?.log(.warning, "audio interruption began")
                    self?.pause()
                }
            },
            onInterruptionEndedShouldResume: { [weak self] in
                Task { @MainActor in
                    self?.log(.info, "audio interruption ended; resuming playback")
                    self?.play()
                }
            },
            onRouteOldDeviceUnavailable: { [weak self] in
                Task { @MainActor in
                    self?.log(.warning, "audio route old device unavailable; pausing playback")
                    self?.pause()
                }
            },
        )
    }

    // Cleanup is handled by stop() — callers should call stop() before releasing.

    // MARK: - Internal Helpers

    func setState(_ newState: PlaybackState) {
        guard state != newState else { return }
        log(.info, "state changed \(state) -> \(newState)")
        state = newState
        nowPlayingManager.updatePlaybackState(newState)
        delegate?.musicPlayer(self, didChangeState: newState)
    }

    var canHandleLikeCommand: Bool {
        currentItem != nil && likeCommandHandler != nil
    }

    func handleLikeCommand() -> MPRemoteCommandHandlerStatus {
        guard currentItem != nil else {
            return .noActionableNowPlayingItem
        }
        guard let likeCommandHandler else {
            return .commandFailed
        }
        return likeCommandHandler() ? .success : .commandFailed
    }
}

public extension MusicPlayer {
    func setPeriodicTimeObserverSuspended(_ suspended: Bool) {
        guard isPeriodicTimeObserverSuspended != suspended else {
            log(.verbose, "setPeriodicTimeObserverSuspended ignored suspended=\(suspended)")
            return
        }

        isPeriodicTimeObserverSuspended = suspended
        log(.info, "setPeriodicTimeObserverSuspended suspended=\(suspended)")

        if suspended {
            if let observer = timeObserver {
                log(.verbose, "removing time observer because updates are suspended")
                engine.removeTimeObserver(observer)
                timeObserver = nil
            }
            return
        }

        guard currentItem != nil else {
            log(.verbose, "time observer resume deferred because current item is missing")
            return
        }

        setupTimeObserver()
    }

    func configureLikeCommand(
        title: String? = nil,
        shortTitle: String? = nil,
        handler: (() -> Bool)? = nil,
    ) {
        likeCommandLocalizedTitle = title ?? String(localized: "Like", bundle: .module)
        likeCommandLocalizedShortTitle = shortTitle
        likeCommandHandler = handler
        remoteCommandManager.updateLikeCommand(
            isEnabled: canHandleLikeCommand,
            isActive: currentItemLiked,
            localizedTitle: likeCommandLocalizedTitle,
            localizedShortTitle: likeCommandLocalizedShortTitle,
        )
    }

    /// Deliver a lyric line to display in the system media center artist field.
    /// Each line auto-expires after 10 seconds unless replaced by the next line.
    /// Pass `nil` to revert to the original artist name immediately.
    func updateNowPlayingSubtitle(_ text: String?) {
        nowPlayingManager.updateSubtitle(text)
    }

    func setCurrentItemLiked(_ isLiked: Bool) {
        currentItemLiked = isLiked
        remoteCommandManager.updateLikeCommand(
            isEnabled: canHandleLikeCommand,
            isActive: currentItemLiked,
            localizedTitle: likeCommandLocalizedTitle,
            localizedShortTitle: likeCommandLocalizedShortTitle,
        )
    }
}
