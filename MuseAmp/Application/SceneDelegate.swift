//
//  SceneDelegate.swift
//  MuseAmp
//
//  Created by @Lakr233 on 2026/04/11.
//

#if targetEnvironment(macCatalyst)
    import Darwin
#endif
import UIKit

@objc(SceneDelegate)
class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var environment: AppEnvironment?
    private weak var mainController: MainController?
    private var pendingAudioImportURLs: [URL] = []
    private var pendingPlaylistImportURLs: [URL] = []
    private var pendingServerProfileImportURLs: [URL] = []
    private var importCoalesceTask: Task<Void, Never>?
    private var pendingReceiverInfo: SyncReceiverHandshakeInfo?

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

        windowScene.sizeRestrictions?.minimumSize = CGSize(width: 650, height: 650)

        #if targetEnvironment(macCatalyst)
            if let titlebar = windowScene.titlebar {
                titlebar.titleVisibility = .hidden
                titlebar.toolbar = nil
            }
            windowScene.sizeRestrictions?.minimumSize = CGSize(width: 800, height: 650)
        #endif

        _ = enqueueURLContexts(connectionOptions.urlContexts)

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
            mc.loadViewIfNeeded()
            mainController = mc
            Interface.transition(with: window, duration: 0.25) {
                window.rootViewController = mc
            }
            Task { @MainActor [environment] in
                _ = await environment.playbackController.restorePersistedPlaybackIfNeeded()
                environment.downloadManager.reconcileOnLaunch()
                environment.backfillAlbumArtistsIfNeeded()
            }
            drainPendingImports()
            drainPendingReceiverInfo()
        }
        window.rootViewController = bootController
    }

    func scene(_: UIScene, openURLContexts contexts: Set<UIOpenURLContext>) {
        guard enqueueURLContexts(contexts) else { return }
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
        #if targetEnvironment(macCatalyst)
            scheduleCatalystExitIfNeededAfterLastWindowCloses()
        #endif
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

    func isImportablePlaylistFile(_ url: URL) -> Bool {
        url.pathExtension.caseInsensitiveCompare(String(PlaylistTransferFileType.fileExtension.dropFirst())) == .orderedSame
    }

    func isImportableServerProfileFile(_ url: URL) -> Bool {
        url.pathExtension.caseInsensitiveCompare("subsonicconfig") == .orderedSame
    }

    /// Queues importable files and routes Apple TV links. Returns whether any
    /// file was queued for import.
    func enqueueURLContexts(_ contexts: Set<UIOpenURLContext>) -> Bool {
        var didEnqueueImport = false
        for context in contexts {
            let url = context.url
            if url.isFileURL, isImportableAudioFile(url) {
                pendingAudioImportURLs.append(url)
                didEnqueueImport = true
            } else if url.isFileURL, isImportablePlaylistFile(url) {
                pendingPlaylistImportURLs.append(url)
                didEnqueueImport = true
            } else if url.isFileURL, isImportableServerProfileFile(url) {
                pendingServerProfileImportURLs.append(url)
                didEnqueueImport = true
            } else if let receiverInfo = parseAppleTVURL(url) {
                handleAppleTVReceiverInfo(receiverInfo)
            }
        }
        return didEnqueueImport
    }

    func dispatchImports(
        audioURLs: [URL],
        playlistURLs: [URL],
        serverProfileURLs: [URL],
    ) {
        if !audioURLs.isEmpty {
            mainController?.performFileImport(urls: audioURLs)
        }
        if !playlistURLs.isEmpty {
            mainController?.performPlaylistImport(urls: playlistURLs)
        }
        if let serverProfileURL = serverProfileURLs.first {
            if serverProfileURLs.count > 1 {
                AppLog.warning(self, "Multiple server profile files received; importing the first one only")
            }
            mainController?.performServerProfileImport(url: serverProfileURL)
        }
    }

    func drainPendingImports() {
        guard !pendingAudioImportURLs.isEmpty
            || !pendingPlaylistImportURLs.isEmpty
            || !pendingServerProfileImportURLs.isEmpty
        else {
            return
        }
        let audioURLs = pendingAudioImportURLs
        let playlistURLs = pendingPlaylistImportURLs
        let serverProfileURLs = pendingServerProfileImportURLs
        pendingAudioImportURLs.removeAll()
        pendingPlaylistImportURLs.removeAll()
        pendingServerProfileImportURLs.removeAll()
        // Dispatch to the next run loop iteration so MainController's view
        // is fully in the window hierarchy before we present the import alert.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            dispatchImports(
                audioURLs: audioURLs,
                playlistURLs: playlistURLs,
                serverProfileURLs: serverProfileURLs,
            )
        }
    }

    func parseAppleTVURL(_ url: URL) -> SyncReceiverHandshakeInfo? {
        guard url.scheme == "museamp", url.host == "tv" else { return nil }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let base64 = components.queryItems?.first(where: { $0.name == "data" })?.value,
              let data = Data(base64Encoded: base64)
        else {
            AppLog.warning(self, "parseAppleTVURL invalid data in URL")
            return nil
        }

        do {
            let info = try JSONDecoder().decode(SyncReceiverHandshakeInfo.self, from: data)
            guard SyncConstants.isCompatible(protocolVersion: info.protocolVersion) else {
                AppLog.warning(self, "parseAppleTVURL protocol mismatch version=\(info.protocolVersion)")
                return nil
            }
            return info
        } catch {
            AppLog.error(self, "parseAppleTVURL decode failed: \(error.localizedDescription)")
            return nil
        }
    }

    func handleAppleTVReceiverInfo(_ receiverInfo: SyncReceiverHandshakeInfo) {
        guard let mainController else {
            pendingReceiverInfo = receiverInfo
            return
        }
        DispatchQueue.main.async {
            mainController.presentAppleTVContentPicker(receiverInfo: receiverInfo)
        }
    }

    func drainPendingReceiverInfo() {
        guard let receiverInfo = pendingReceiverInfo else { return }
        pendingReceiverInfo = nil
        DispatchQueue.main.async { [weak self] in
            self?.mainController?.presentAppleTVContentPicker(receiverInfo: receiverInfo)
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
            guard mainController != nil else { return }

            let audioURLs = pendingAudioImportURLs
            let playlistURLs = pendingPlaylistImportURLs
            let serverProfileURLs = pendingServerProfileImportURLs
            pendingAudioImportURLs.removeAll()
            pendingPlaylistImportURLs.removeAll()
            pendingServerProfileImportURLs.removeAll()

            dispatchImports(
                audioURLs: audioURLs,
                playlistURLs: playlistURLs,
                serverProfileURLs: serverProfileURLs,
            )
        }
    }
}

#if targetEnvironment(macCatalyst)
    extension SceneDelegate {
        var appEnvironment: AppEnvironment? {
            environment
        }

        private func scheduleCatalystExitIfNeededAfterLastWindowCloses() {
            Task { @MainActor [weak self] in
                guard let self else { return }
                try? await Task.sleep(for: .milliseconds(200))
                let remainingWindowSceneCount = connectedWindowSceneCount()
                guard MacCatalystTerminationPolicy.shouldExitAfterSceneDisconnect(
                    remainingWindowSceneCount: remainingWindowSceneCount,
                ) else {
                    AppLog.info(
                        self,
                        "sceneDidDisconnect keeping app alive remainingWindowScenes=\(remainingWindowSceneCount)",
                    )
                    return
                }
                prepareForImmediateTermination()
                AppLog.info(self, "sceneDidDisconnect last window closed - exiting app")
                Darwin.exit(0)
            }
        }

        func prepareForImmediateTermination() {
            environment?.playbackController.persistPlaybackState()
            environment?.playbackController.setUIPublishingSuspended(true)
        }

        private func connectedWindowSceneCount() -> Int {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .count
        }
    }
#endif
