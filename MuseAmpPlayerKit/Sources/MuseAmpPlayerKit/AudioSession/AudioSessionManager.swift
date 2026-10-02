//
//  AudioSessionManager.swift
//  MuseAmpPlayerKit
//
//  Created by @Lakr233 on 2026/04/11.
//

import AVFoundation

@MainActor
final class AudioSessionManager {
    /// `AVAudioSession.setActive` blocks while the system negotiates the
    /// session, so activation runs on this serial queue instead of the main
    /// thread. Serial ordering keeps activate/deactivate pairs in sequence.
    private static let sessionQueue = DispatchQueue(
        label: "MuseAmpPlayerKit.AudioSessionManager",
        qos: .userInitiated,
    )

    private let logger: any MusicPlayerLogger

    init(logger: any MusicPlayerLogger = NoopMusicPlayerLogger()) {
        self.logger = logger
    }

    func configure(
        onInterruptionBegan: @escaping @Sendable () -> Void,
        onInterruptionEndedShouldResume: @escaping @Sendable () -> Void,
        onRouteOldDeviceUnavailable: @escaping @Sendable () -> Void,
    ) {
        #if os(iOS) || os(tvOS) || os(watchOS)
            let session = AVAudioSession.sharedInstance()
            do {
                try session.setCategory(
                    .playback,
                    mode: .default,
                    policy: .longFormAudio,
                    options: [],
                )
                log(
                    .info,
                    "configured audio session category=\(session.category.rawValue) mode=\(session.mode.rawValue) routeSharingPolicy=\(session.routeSharingPolicy.rawValue)",
                )
            } catch {
                log(
                    .warning,
                    "failed to configure long-form audio route sharing policy error=\(describe(error: error))",
                )
                try? session.setCategory(.playback, mode: .default)
                log(
                    .info,
                    "fell back to audio session category=\(session.category.rawValue) mode=\(session.mode.rawValue) routeSharingPolicy=\(session.routeSharingPolicy.rawValue)",
                )
            }

            // Both observers stay registered for the process lifetime; nothing removes them.
            _ = NotificationCenter.default.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: session,
                queue: .main,
            ) { notification in
                guard let info = notification.userInfo,
                      let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                      let type = AVAudioSession.InterruptionType(rawValue: typeValue)
                else { return }

                switch type {
                case .began:
                    onInterruptionBegan()
                case .ended:
                    if let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt {
                        let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                        if options.contains(.shouldResume) {
                            onInterruptionEndedShouldResume()
                        }
                    }
                @unknown default:
                    break
                }
            }

            _ = NotificationCenter.default.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: session,
                queue: .main,
            ) { notification in
                guard let info = notification.userInfo,
                      let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
                      let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue)
                else { return }

                if reason == .oldDeviceUnavailable {
                    onRouteOldDeviceUnavailable()
                }
            }
        #endif
    }

    func activate() {
        #if os(iOS) || os(tvOS) || os(watchOS)
            let logger = logger
            Self.sessionQueue.async {
                do {
                    try AVAudioSession.sharedInstance().setActive(true)
                } catch {
                    logger.log(
                        level: .warning,
                        component: "AudioSessionManager",
                        message: "failed to activate audio session error=\(error.localizedDescription)",
                    )
                }
            }
        #endif
    }

    func deactivate() {
        #if os(iOS) || os(tvOS) || os(watchOS)
            let logger = logger
            Self.sessionQueue.async {
                do {
                    try AVAudioSession.sharedInstance().setActive(
                        false,
                        options: .notifyOthersOnDeactivation,
                    )
                } catch {
                    logger.log(
                        level: .warning,
                        component: "AudioSessionManager",
                        message: "failed to deactivate audio session error=\(error.localizedDescription)",
                    )
                }
            }
        #endif
    }

    private func log(_ level: MusicPlayerLogLevel, _ message: String) {
        logger.log(level: level, component: "AudioSessionManager", message: message)
    }

    private func describe(error: any Error) -> String {
        let nsError = error as NSError
        return "domain=\(nsError.domain) code=\(nsError.code) description=\(nsError.localizedDescription)"
    }
}
