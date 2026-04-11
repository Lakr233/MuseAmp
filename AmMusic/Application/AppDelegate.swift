//
//  AppDelegate.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import AlertController
@_exported import AmMusicKit
import UIKit

@objc(AppDelegate)
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil,
    ) -> Bool {
        AlertControllerConfiguration.alertImage = Bundle.appIcon
        AlertControllerConfiguration.accentColor = .accent
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
