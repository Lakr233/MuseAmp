//
//  SceneDelegate.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import UIKit

@objc(SceneDelegate)
class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var environment: AppEnvironment?
    private weak var mainController: MainController?
    private var pendingImportURLs: [URL] = []
    private var importCoalesceTask: Task<Void, Never>?

    func scene(
        _ scene: UIScene, willConnectTo _: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions,
    ) {
        guard let windowScene = (scene as? UIWindowScene) else {
            AppLog.warning(
                self,
                "Scene is not a UIWindowScene (actual type: \(type(of: scene))) - aborting window setup",
            )
            return
        }

        #if targetEnvironment(macCatalyst)
            if let titlebar = windowScene.titlebar {
                titlebar.titleVisibility = .hidden
                let toolbar = NSToolbar(identifier: "main")
                toolbar.displayMode = .default
                titlebar.toolbar = toolbar
            }
            windowScene.sizeRestrictions?.minimumSize = CGSize(width: 650, height: 650)
        #endif

        for urlContext in connectionOptions.urlContexts {
            let url = urlContext.url
            if url.isFileURL, isImportableAudioFile(url) {
                pendingImportURLs.append(url)
            }
        }

        let window = UIWindow(windowScene: windowScene)
        window.clipsToBounds = true
        defer {
            window.makeKeyAndVisible()
            self.window = window
        }
        window.tintColor = .accent
        let bootController = BootProgressController()
        bootController.onBootComplete = { [weak self, weak window] environment in
            guard let self, let window else {
                return
            }
            self.environment = environment
            let mc = MainController(environment: environment)
            mainController = mc
            window.rootViewController = mc
            Task { @MainActor [environment] in
                _ = await environment.playbackController.restorePersistedPlaybackIfNeeded()
                environment.downloadManager.reconcileOnLaunch()
            }
            drainPendingImports()
        }
        window.rootViewController = bootController
    }

    func scene(_: UIScene, openURLContexts contexts: Set<UIOpenURLContext>) {
        let audioURLs = contexts
            .map(\.url)
            .filter { $0.isFileURL && isImportableAudioFile($0) }
        guard !audioURLs.isEmpty else { return }

        pendingImportURLs.append(contentsOf: audioURLs)
        scheduleCoalescedImport()
    }

    func sceneWillResignActive(_: UIScene) {
        environment?.playbackController.setUIPublishingSuspended(true)
        environment?.playbackController.persistPlaybackState()
    }

    func sceneDidBecomeActive(_: UIScene) {
        environment?.playbackController.setUIPublishingSuspended(false)
    }

    func sceneDidEnterBackground(_: UIScene) {
        environment?.playbackController.persistPlaybackState()
    }

    func sceneDidDisconnect(_: UIScene) {
        environment?.playbackController.setUIPublishingSuspended(true)
        environment?.playbackController.persistPlaybackState()
    }
}

// MARK: - File Import Handling

private extension SceneDelegate {
    static let importableExtensions: Set<String> = [
        "mp3", "m4a", "flac", "wav", "aac", "aiff", "alac", "ogg", "wma", "opus",
    ]

    func isImportableAudioFile(_ url: URL) -> Bool {
        Self.importableExtensions.contains(url.pathExtension.lowercased())
    }

    func drainPendingImports() {
        guard !pendingImportURLs.isEmpty else { return }
        let urls = pendingImportURLs
        pendingImportURLs.removeAll()
        // Dispatch to the next run loop iteration so MainController's view
        // is fully in the window hierarchy before we present the import alert.
        DispatchQueue.main.async { [weak self] in
            self?.mainController?.performFileImport(urls: urls)
        }
    }

    /// iOS may deliver files from the Files app across multiple rapid
    /// `openURLContexts` calls (one per file). Coalesce them into a single
    /// import batch by waiting briefly before dispatching.
    func scheduleCoalescedImport() {
        importCoalesceTask?.cancel()
        importCoalesceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled, let self else { return }
            guard let mainController, !pendingImportURLs.isEmpty else { return }
            let urls = pendingImportURLs
            pendingImportURLs.removeAll()
            mainController.performFileImport(urls: urls)
        }
    }
}
