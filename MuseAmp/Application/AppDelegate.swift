//
//  AppDelegate.swift
//  MuseAmp
//
//  Created by @Lakr233 on 2026/04/11.
//

@preconcurrency import AlertController
@_exported import SubsonicClientKit
#if targetEnvironment(macCatalyst)
    import Darwin
#endif
import UIKit

@objc(AppDelegate)
class AppDelegate: UIResponder, UIApplicationDelegate {
    #if targetEnvironment(macCatalyst)
        private var isPresentingExitConfirmation = false
    #endif

    func application(
        _: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil,
    ) -> Bool {
        AlertControllerConfiguration.alertImage = Bundle.appIcon
        AlertControllerConfiguration.accentColor = .accent
        AppEnvironment.bootstrapLogging()
        // No transfer can be running yet, so any scratch directory left by
        // a crash or kill is stale.
        SyncTransferSession.removeStaleTemporaryDirectories()
        return true
    }

    func application(
        _: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options _: UIScene.ConnectionOptions,
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: "Default Configuration",
            sessionRole: connectingSceneSession.role,
        )
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }

    #if targetEnvironment(macCatalyst)
        override func buildMenu(with builder: any UIMenuBuilder) {
            super.buildMenu(with: builder)
            guard builder.system === UIMenuSystem.main else {
                return
            }

            let closeCommand = UIKeyCommand(
                input: "w",
                modifierFlags: .command,
                action: #selector(requestAppExitFromMenu(_:)),
            )
            closeCommand.title = String(localized: "Close Window")
            closeCommand.discoverabilityTitle = String(localized: "Close Window")
            closeCommand.wantsPriorityOverSystemBehavior = true

            let quitCommand = UIKeyCommand(
                input: "q",
                modifierFlags: .command,
                action: #selector(requestAppExitFromMenu(_:)),
            )
            quitCommand.title = catalystQuitMenuTitle
            quitCommand.discoverabilityTitle = catalystQuitMenuTitle
            quitCommand.wantsPriorityOverSystemBehavior = true

            builder.replace(
                menu: .close,
                with: UIMenu(
                    title: "",
                    image: nil,
                    identifier: .close,
                    options: .displayInline,
                    children: [closeCommand],
                ),
            )

            builder.replace(
                menu: .quit,
                with: UIMenu(
                    title: "",
                    image: nil,
                    identifier: .quit,
                    options: .displayInline,
                    children: [quitCommand],
                ),
            )
        }

        @objc
        func requestAppExitFromMenu(_: Any?) {
            requestApplicationExit()
        }

        @objc
        func terminate(_: Any?) {
            requestApplicationExit()
        }

        @objc
        override func performClose(_: Any?) {
            requestApplicationExit()
        }

        func requestApplicationExit() {
            requestProtectedTermination { [weak self] in
                self?.terminateCatalystApplication(reason: "requested from app delegate exit hook")
            }
        }

        var mainWindow: UIWindow? {
            let windowScenes = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
            let windows = windowScenes.flatMap(\.windows)
            return windows.first(where: \.isKeyWindow) ?? windows.first
        }

        private var hasExecutingTasks: Bool {
            guard let environment = preferredCatalystSceneDelegate()?.appEnvironment else {
                return false
            }
            return MacCatalystTerminationPolicy.shouldConfirmTermination(
                for: environment.playbackController.snapshot,
                hasExecutingDownloads: environment.downloadManager.hasExecutingTasks,
            )
        }

        private func requestProtectedTermination(_ action: @escaping () -> Void) {
            guard hasExecutingTasks else {
                action()
                return
            }
            presentExitConfirmationIfNeeded(action: action)
        }

        private func presentExitConfirmationIfNeeded(action: @escaping () -> Void) {
            guard !isPresentingExitConfirmation else {
                AppLog.info(self, "presentExitConfirmationIfNeeded confirmation already visible")
                return
            }
            guard let presenter = topViewControllerForExitPrompt() else {
                AppLog.warning(self, "presentExitConfirmationIfNeeded no presenter available")
                action()
                return
            }

            isPresentingExitConfirmation = true
            ConfirmationAlertPresenter.present(
                on: presenter,
                title: String(localized: "Quit"),
                message: String(localized: "Quitting now will interrupt the current playback or download."),
                confirmTitle: String(localized: "Quit"),
                onCancel: { [weak self] in
                    self?.isPresentingExitConfirmation = false
                },
                onConfirm: { [weak self] in
                    self?.isPresentingExitConfirmation = false
                    action()
                },
            )
        }

        private func terminateCatalystApplication(reason: String) {
            AppLog.info(self, "terminateCatalystApplication reason=\(reason)")
            preferredCatalystSceneDelegate()?.prepareForImmediateTermination()
            terminateApplication()
        }

        private var catalystQuitMenuTitle: String {
            let fallbackName = "MuseAmp"
            let appName = (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                ?? (Bundle.main.object(forInfoDictionaryKey: kCFBundleNameKey as String) as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                ?? fallbackName
            return String(format: String(localized: "Quit %@"), appName)
        }

        private func preferredCatalystSceneDelegate() -> SceneDelegate? {
            let delegates = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .compactMap { $0.delegate as? SceneDelegate }
            return delegates.first(where: { $0.window?.isKeyWindow == true }) ?? delegates.first
        }

        private func topViewControllerForExitPrompt() -> UIViewController? {
            guard let rootViewController = mainWindow?.rootViewController else {
                return nil
            }
            return deepestPresentedViewController(startingAt: rootViewController)
        }

        private func deepestPresentedViewController(startingAt viewController: UIViewController) -> UIViewController {
            var candidate = viewController
            while let presentedViewController = candidate.presentedViewController {
                candidate = presentedViewController
            }
            return candidate
        }
    #endif

    // MARK: - Background URL Session

    private var backgroundCompletionHandler: (() -> Void)?

    func application(
        _: UIApplication,
        handleEventsForBackgroundURLSession _: String,
        completionHandler: @escaping () -> Void,
    ) {
        backgroundCompletionHandler = completionHandler
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession _: URLSession) {
        Task { @MainActor in
            if self.backgroundCompletionHandler != nil {
                self.backgroundCompletionHandler?()
                self.backgroundCompletionHandler = nil
            } else {
                AppLog.warning(self, "No background completion handler stored to invoke")
            }
        }
    }
}

func terminateApplication() -> Never {
    #if targetEnvironment(macCatalyst)
        Darwin.exit(0)
    #else
        UIApplication.shared.perform(#selector(NSXPCConnection.suspend))
        Task.detached {
            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                AppLog.warning("AppDelegate", "termination delay interrupted error=\(error)")
            }
            exit(0)
        }
        sleep(5)
        fatalError()
    #endif
}
