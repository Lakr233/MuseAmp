//
//  SyncBackgroundInterruptionObserver.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/12.
//

import Foundation
import UIKit

final class SyncBackgroundInterruptionObserver {
    private let notificationCenter: NotificationCenter
    private let onDidEnterBackground: () -> Void

    private var didEnterBackgroundObserver: NSObjectProtocol?

    init(
        notificationCenter: NotificationCenter = .default,
        onDidEnterBackground: @escaping () -> Void,
    ) {
        self.notificationCenter = notificationCenter
        self.onDidEnterBackground = onDidEnterBackground
    }

    deinit {
        stop()
    }

    func start() {
        guard didEnterBackgroundObserver == nil else {
            return
        }

        didEnterBackgroundObserver = notificationCenter.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: nil,
        ) { [weak self] _ in
            self?.onDidEnterBackground()
        }
    }

    func stop() {
        guard let didEnterBackgroundObserver else {
            return
        }

        notificationCenter.removeObserver(didEnterBackgroundObserver)
        self.didEnterBackgroundObserver = nil
    }
}
