import AVFoundation

@MainActor
final class AudioSessionManager {
    private let logger: any MusicPlayerLogger
    private var interruptionObserver: (any NSObjectProtocol)?
    private var routeChangeObserver: (any NSObjectProtocol)?
    private var onInterruptionBegan: (@Sendable () -> Void)?
    private var onInterruptionEndedShouldResume: (@Sendable () -> Void)?
    private var onRouteOldDeviceUnavailable: (@Sendable () -> Void)?

    init(logger: any MusicPlayerLogger = NoopMusicPlayerLogger()) {
        self.logger = logger
    }

    func configure(
        onInterruptionBegan: @escaping @Sendable () -> Void,
        onInterruptionEndedShouldResume: @escaping @Sendable () -> Void,
        onRouteOldDeviceUnavailable: @escaping @Sendable () -> Void
    ) {
        self.onInterruptionBegan = onInterruptionBegan
        self.onInterruptionEndedShouldResume = onInterruptionEndedShouldResume
        self.onRouteOldDeviceUnavailable = onRouteOldDeviceUnavailable

        #if os(iOS) || os(tvOS) || os(watchOS)
            let session = AVAudioSession.sharedInstance()
            do {
                try session.setCategory(
                    .playback,
                    mode: .default,
                    policy: .longFormAudio,
                    options: []
                )
                log(
                    .info,
                    "configured audio session category=\(session.category.rawValue) mode=\(session.mode.rawValue) routeSharingPolicy=\(session.routeSharingPolicy.rawValue)"
                )
            } catch {
                log(
                    .warning,
                    "failed to configure long-form audio route sharing policy error=\(describe(error: error))"
                )
                try? session.setCategory(.playback, mode: .default)
                log(
                    .info,
                    "fell back to audio session category=\(session.category.rawValue) mode=\(session.mode.rawValue) routeSharingPolicy=\(session.routeSharingPolicy.rawValue)"
                )
            }

            let beganHandler = onInterruptionBegan
            let resumeHandler = onInterruptionEndedShouldResume
            let routeHandler = onRouteOldDeviceUnavailable

            interruptionObserver = NotificationCenter.default.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: session,
                queue: .main
            ) { notification in
                guard let info = notification.userInfo,
                      let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                      let type = AVAudioSession.InterruptionType(rawValue: typeValue)
                else { return }

                switch type {
                case .began:
                    beganHandler()
                case .ended:
                    if let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt {
                        let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                        if options.contains(.shouldResume) {
                            resumeHandler()
                        }
                    }
                @unknown default:
                    break
                }
            }

            routeChangeObserver = NotificationCenter.default.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: session,
                queue: .main
            ) { notification in
                guard let info = notification.userInfo,
                      let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
                      let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue)
                else { return }

                if reason == .oldDeviceUnavailable {
                    routeHandler()
                }
            }
        #endif
    }

    func activate() {
        #if os(iOS) || os(tvOS) || os(watchOS)
            try? AVAudioSession.sharedInstance().setActive(true)
        #endif
    }

    func deactivate() {
        #if os(iOS) || os(tvOS) || os(watchOS)
            try? AVAudioSession.sharedInstance().setActive(
                false,
                options: .notifyOthersOnDeactivation
            )
        #endif
    }

    func teardown() {
        if let obs = interruptionObserver {
            NotificationCenter.default.removeObserver(obs)
            interruptionObserver = nil
        }
        if let obs = routeChangeObserver {
            NotificationCenter.default.removeObserver(obs)
            routeChangeObserver = nil
        }
    }

    private func log(_ level: MusicPlayerLogLevel, _ message: String) {
        logger.log(level: level, component: "AudioSessionManager", message: message)
    }

    private func describe(error: any Error) -> String {
        let nsError = error as NSError
        return "domain=\(nsError.domain) code=\(nsError.code) description=\(nsError.localizedDescription)"
    }
}
