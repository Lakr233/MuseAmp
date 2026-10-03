//
//  TVAppDelegate.swift
//  MuseAmpTV
//
//  Created by @Lakr233 on 2026/04/11.
//

import UIKit

@objc(TVAppDelegate)
final class TVAppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil,
    ) -> Bool {
        TVAppContext.bootstrapLogging()
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
        configuration.delegateClass = TVSceneDelegate.self
        return configuration
    }
}
