//
//  MediaCenterCoordinator.swift
//  AmMusicPlayerKit
//
//  Created by @Lakr233 on 2026/04/11.
//

import AVFoundation
import MediaPlayer

@MainActor
protocol NowPlayingStatePublishing: AnyObject {
    var nowPlayingInfo: [String: Any]? { get set }
    var playbackState: MPNowPlayingPlaybackState { get set }
}

@MainActor
protocol RemoteCommandCenterProviding: AnyObject {
    var commandCenter: MPRemoteCommandCenter { get }
}

@MainActor
protocol MediaCenterBackend: NowPlayingStatePublishing, RemoteCommandCenterProviding {
    func activateSessionIfPossible()
}

@MainActor
final class MediaCenterCoordinator: NowPlayingStatePublishing, RemoteCommandCenterProviding {
    enum BackendKind {
        case legacy
        case session
    }

    let backendKind: BackendKind

    private let backend: any MediaCenterBackend

    init(
        engine: any AudioPlaybackEngine,
        logger: any MusicPlayerLogger = NoopMusicPlayerLogger(),
    ) {
        #if os(iOS) || os(tvOS)
            if #available(iOS 16.0, tvOS 14.0, *),
               let player = engine.mediaCenterPlayer
            {
                let backend = SessionMediaCenterBackend(player: player, logger: logger)
                self.backend = backend
                backendKind = .session
            } else {
                let backend = LegacyMediaCenterBackend()
                self.backend = backend
                backendKind = .legacy
            }
        #else
            let backend = LegacyMediaCenterBackend()
            self.backend = backend
            backendKind = .legacy
        #endif
    }

    init(
        backend: any MediaCenterBackend,
        backendKind: BackendKind,
    ) {
        self.backend = backend
        self.backendKind = backendKind
    }

    var nowPlayingInfo: [String: Any]? {
        get { backend.nowPlayingInfo }
        set { backend.nowPlayingInfo = newValue }
    }

    var playbackState: MPNowPlayingPlaybackState {
        get { backend.playbackState }
        set { backend.playbackState = newValue }
    }

    var commandCenter: MPRemoteCommandCenter {
        backend.commandCenter
    }

    func activateSessionIfPossible() {
        backend.activateSessionIfPossible()
    }
}

@MainActor
final class LegacyMediaCenterBackend: MediaCenterBackend {
    private let nowPlayingInfoCenter = MPNowPlayingInfoCenter.default()

    var nowPlayingInfo: [String: Any]? {
        get { nowPlayingInfoCenter.nowPlayingInfo }
        set { nowPlayingInfoCenter.nowPlayingInfo = newValue }
    }

    var playbackState: MPNowPlayingPlaybackState {
        get { nowPlayingInfoCenter.playbackState }
        set { nowPlayingInfoCenter.playbackState = newValue }
    }

    var commandCenter: MPRemoteCommandCenter {
        MPRemoteCommandCenter.shared()
    }

    func activateSessionIfPossible() {}
}

#if os(iOS) || os(tvOS)
    @available(iOS 16.0, tvOS 14.0, *)
    @MainActor
    final class SessionMediaCenterBackend: MediaCenterBackend {
        private let logger: any MusicPlayerLogger
        private let session: MPNowPlayingSession

        init(player: AVPlayer, logger: any MusicPlayerLogger) {
            self.logger = logger
            session = MPNowPlayingSession(players: [player])
            session.automaticallyPublishesNowPlayingInfo = false
        }

        var nowPlayingInfo: [String: Any]? {
            get { session.nowPlayingInfoCenter.nowPlayingInfo }
            set { session.nowPlayingInfoCenter.nowPlayingInfo = newValue }
        }

        var playbackState: MPNowPlayingPlaybackState {
            get { session.nowPlayingInfoCenter.playbackState }
            set { session.nowPlayingInfoCenter.playbackState = newValue }
        }

        var commandCenter: MPRemoteCommandCenter {
            session.remoteCommandCenter
        }

        func activateSessionIfPossible() {
            guard session.canBecomeActive else {
                log(.verbose, "activateSessionIfPossible skipped because session cannot become active")
                return
            }

            session.becomeActiveIfPossible { [logger] changed in
                logger.log(
                    level: changed ? .info : .verbose,
                    component: "MediaCenterCoordinator",
                    message: "becomeActiveIfPossible changed=\(changed)",
                )
            }
        }

        private func log(_ level: MusicPlayerLogLevel, _ message: String) {
            logger.log(level: level, component: "MediaCenterCoordinator", message: message)
        }
    }
#endif
