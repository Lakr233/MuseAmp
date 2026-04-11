//
//  MainController.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import AlertController
import Combine
import ConfigurableKit
import LNPopupController
import Then
import UIKit

nonisolated enum RootDestination: Int, CaseIterable, Hashable {
    case library
    case albums
    case songs
    case downloads
    case playlistList
    case search
    case settings

    var title: String {
        switch self {
        case .library:
            String(localized: "Library")
        case .albums:
            String(localized: "Albums")
        case .songs:
            String(localized: "Songs")
        case .downloads:
            String(localized: "Downloads")
        case .search:
            String(localized: "Search")
        case .settings:
            String(localized: "Settings")
        case .playlistList:
            String(localized: "Playlist")
        }
    }

    var imageName: String {
        switch self {
        case .library:
            "music.note.house"
        case .albums:
            "square.stack"
        case .songs:
            "music.note"
        case .downloads:
            "arrow.down.circle"
        case .search:
            "magnifyingglass"
        case .settings:
            "gearshape"
        case .playlistList:
            "music.note.list"
        }
    }
}

nonisolated enum LayoutMode: Equatable {
    case compact
    case relaxed
    case catalyst
}

class MainController: UIViewController {
    let environment: AppEnvironment

    private(set) var currentLayoutMode: LayoutMode?
    private(set) var selectedDestination: RootDestination = .albums
    private(set) var selectedPlaylistID: UUID?

    // MARK: - Child Controllers

    private(set) lazy var compactTabBarController = TabBarController(environment: environment)
    private(set) lazy var sidebarViewController = SidebarViewController(environment: environment)
    private(set) lazy var contentContainerController = UIViewController()
    private(set) lazy var rootSplitViewController = UISplitViewController(style: .doubleColumn)
    private(set) lazy var navigationCoordinator = AppNavigationCoordinator(environment: environment)

    private var contentNavigationControllers: [RootDestination: UINavigationController] = [:]
    private var playlistNavigationControllers: [UUID: UINavigationController] = [:]

    // MARK: - Popup State (relaxed/catalyst)

    var cancellables: Set<AnyCancellable> = []
    var popupArtworkTask: Task<Void, Never>?
    var popupArtworkURL: URL?
    lazy var popupPlayPauseItem = UIBarButtonItem(
        image: UIImage(systemName: "play.fill"),
        primaryAction: UIAction { [weak self] _ in
            self?.environment.playbackController.togglePlayPause()
        },
    ).then { $0.accessibilityIdentifier = "popup.playPause" }
    lazy var popupNextItem = UIBarButtonItem(
        image: UIImage(systemName: "forward.fill"),
        primaryAction: UIAction { [weak self] _ in
            self?.environment.playbackController.next()
        },
    ).then { $0.accessibilityIdentifier = "popup.next" }
    var nowPlayingPopupContentViewController: NowPlayingRelaxedController?
    var isNowPlayingPopupOpen = false
    private(set) lazy var popupPagingHandler = PopupBarPagingHandler(
        playbackController: environment.playbackController,
        onRequestUpdate: { [weak self] in
            guard let self else { return }
            updateNowPlayingPopupItem(using: environment.playbackController.snapshot)
        },
    )

    // MARK: - Popup Context Menu

    lazy var popupPlaybackMenuProvider = PlaybackMenuProvider(
        playbackController: environment.playbackController,
    )
    lazy var popupPlaylistMenuProvider = AddToPlaylistMenuProvider(
        playlistStore: environment.playlistStore,
        viewController: self,
    )
    lazy var popupSongContextMenuProvider = SongContextMenuProvider(
        playlistMenuProvider: popupPlaylistMenuProvider,
    )

    // MARK: - Init

    init(environment: AppEnvironment) {
        self.environment = environment
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        view.clipsToBounds = true

        sidebarViewController.onDestinationSelected = { [weak self] destination in
            self?.selectDestination(destination)
        }
        sidebarViewController.onPlaylistSelected = { [weak self] playlistID in
            self?.openPlaylistDetail(playlistID: playlistID)
        }
        sidebarViewController.onSettingsTapped = { [weak self] in
            self?.presentSettingsSheet()
        }
        sidebarViewController.onPlaylistsDidReload = { [weak self] playlistIDs in
            self?.cleanupStalePlaylistControllers(activeIDs: Set(playlistIDs))
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let mode = computeLayoutMode()
        guard mode != currentLayoutMode else { return }
        transitionToMode(mode)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?.horizontalSizeClass != traitCollection.horizontalSizeClass else { return }
        let mode = computeLayoutMode()
        guard mode != currentLayoutMode else { return }
        transitionToMode(mode)
    }

    override var childForStatusBarHidden: UIViewController? {
        if currentLayoutMode == .compact {
            return compactTabBarController
        }
        if isNowPlayingPopupOpen, let nowPlayingPopupContentViewController {
            return nowPlayingPopupContentViewController
        }
        return activeContentNavigationController
    }

    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation {
        .fade
    }

    // MARK: - Mode Computation

    private func computeLayoutMode() -> LayoutMode {
        #if targetEnvironment(macCatalyst)
            return .catalyst
        #else
            if traitCollection.horizontalSizeClass == .compact {
                return .compact
            }
            return .relaxed
        #endif
    }

    // MARK: - Mode Transition

    func transitionToMode(_ mode: LayoutMode) {
        let previousMode = currentLayoutMode
        currentLayoutMode = mode

        switch mode {
        case .compact:
            teardownRelaxedLayout()
            installCompactLayout()
        case .relaxed:
            teardownCompactLayout()
            installRelaxedLayout()
        case .catalyst:
            teardownCompactLayout()
            installCatalystLayout()
        }

        if mode != .compact, previousMode == nil || previousMode == .compact {
            bindPlaybackPopup()
        } else if mode == .compact, previousMode != nil, previousMode != .compact {
            unbindPlaybackPopup()
        }
    }

    // MARK: - Destination Selection

    func selectDestination(_ destination: RootDestination) {
        guard currentLayoutMode != .compact else { return }

        if contentContainerController.popupPresentationState == .open {
            contentContainerController.closePopup(animated: true)
        }

        selectedDestination = destination
        selectedPlaylistID = nil
        let nav = contentNavigationController(for: destination)
        installContentNavigationController(nav)
        navigationCoordinator.rootViewController = nav

        if rootSplitViewController.displayMode == .oneOverSecondary {
            InterfaceAnimate.quickAnimate(duration: 0.25) {
                self.rootSplitViewController.preferredDisplayMode = .secondaryOnly
            } completion: { _ in
                self.rootSplitViewController.preferredDisplayMode = .automatic
            }
        }
    }

    func openPlaylistDetail(playlistID: UUID) {
        guard currentLayoutMode != .compact else { return }

        if contentContainerController.popupPresentationState == .open {
            contentContainerController.closePopup(animated: true)
        }

        selectedPlaylistID = playlistID
        let nav = playlistNavigationController(for: playlistID)
        installContentNavigationController(nav)
        navigationCoordinator.rootViewController = nav

        if rootSplitViewController.displayMode == .oneOverSecondary {
            InterfaceAnimate.quickAnimate(duration: 0.25) {
                self.rootSplitViewController.preferredDisplayMode = .secondaryOnly
            } completion: { _ in
                self.rootSplitViewController.preferredDisplayMode = .automatic
            }
        }
    }

    // MARK: - Playlist Navigation Controller Factory

    func playlistNavigationController(for playlistID: UUID) -> UINavigationController {
        if let existing = playlistNavigationControllers[playlistID] {
            return existing
        }

        let detailVC = PlaylistDetailViewController(playlistID: playlistID, environment: environment)
        let nav = UINavigationController(rootViewController: detailVC).then {
            $0.navigationBar.prefersLargeTitles = false
        }
        playlistNavigationControllers[playlistID] = nav
        return nav
    }

    func cleanupStalePlaylistControllers(activeIDs: Set<UUID>) {
        let staleIDs = playlistNavigationControllers.keys.filter { !activeIDs.contains($0) }
        for id in staleIDs {
            let nav = playlistNavigationControllers.removeValue(forKey: id)
            if nav?.parent != nil {
                nav?.willMove(toParent: nil)
                nav?.view.removeFromSuperview()
                nav?.removeFromParent()
            }
        }

        if let selectedPlaylistID, !activeIDs.contains(selectedPlaylistID) {
            self.selectedPlaylistID = nil
            selectDestination(.playlistList)
            sidebarViewController.selectItem(.destination(.playlistList))
        }
    }

    // MARK: - Settings Sheet

    func presentSettingsSheet() {
        let settingsVC = SettingsViewController(environment: environment)
        let nav = UINavigationController(rootViewController: settingsVC).then {
            $0.navigationBar.prefersLargeTitles = false
            $0.modalPresentationStyle = .formSheet
            $0.modalTransitionStyle = .coverVertical
            $0.preferredContentSize = CGSize(width: 550, height: 550)
        }
        settingsVC.navigationItem.rightBarButtonItem = UIBarButtonItem(
            systemItem: .done,
            primaryAction: UIAction { [weak nav] _ in
                nav?.dismiss(animated: true)
            },
        )
        present(nav, animated: true)
    }

    // MARK: - Content Navigation Controller Factory

    func contentNavigationController(for destination: RootDestination) -> UINavigationController {
        if let existing = contentNavigationControllers[destination] {
            return existing
        }

        let rootVC: UIViewController = switch destination {
        case .library, .albums:
            SongLibraryViewController(environment: environment).then {
                $0.title = destination.title
            }
        case .songs:
            SongsViewController(environment: environment).then {
                $0.title = destination.title
            }
        case .downloads:
            DownloadsViewController(downloadManager: environment.downloadManager, environment: environment).then {
                $0.title = destination.title
            }
        case .search:
            SearchViewController(environment: environment).then {
                $0.title = destination.title
            }
        case .settings:
            SettingsViewController(environment: environment).then {
                $0.title = destination.title
            }
        case .playlistList:
            PlaylistViewController(environment: environment).then {
                $0.title = destination.title
            }
        }

        let nav = UINavigationController(rootViewController: rootVC).then {
            $0.navigationBar.prefersLargeTitles = destination != .search
        }
        contentNavigationControllers[destination] = nav
        return nav
    }

    var activeContentNavigationController: UINavigationController? {
        if let selectedPlaylistID {
            return playlistNavigationControllers[selectedPlaylistID]
        }
        return contentNavigationControllers[selectedDestination]
    }

    // MARK: - External File Import

    func performFileImport(urls: [URL]) {
        guard !urls.isEmpty else { return }

        let alert = AlertProgressIndicatorViewController(
            title: String(localized: "Importing"),
            message: String(localized: "Reading audio files..."),
        )
        present(alert, animated: true)

        Task { [weak self, importer = environment.audioFileImporter] in
            let result = await importer.importFiles(urls: urls) { current, total in
                alert.progressContext.purpose(
                    message: String(localized: "Importing \(current) / \(total)..."),
                )
            }

            self?.cleanupInbox()

            await MainActor.run { [weak self] in
                alert.dismiss(animated: true) {
                    self?.showFileImportResult(result)
                }
            }
        }
    }

    private func showFileImportResult(_ result: AudioImportResult) {
        var lines: [String] = []
        if result.succeeded > 0 {
            lines.append(String(localized: "\(result.succeeded) song(s) imported."))
        }
        if result.duplicates > 0 {
            lines.append(String(localized: "\(result.duplicates) duplicate(s) skipped."))
        }
        if result.noMetadata > 0 {
            lines.append(String(localized: "\(result.noMetadata) file(s) had no metadata."))
        }
        if result.errors > 0 {
            lines.append(String(localized: "\(result.errors) file(s) failed."))
        }

        let alert = AlertViewController(
            title: String(localized: "Import Complete"),
            message: lines.joined(separator: "\n"),
        ) { context in
            context.addAction(title: String(localized: "OK"), attribute: .accent) {
                context.dispose()
            }
        }
        present(alert, animated: true)
    }

    private nonisolated func cleanupInbox() {
        let inbox = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Inbox", isDirectory: true)
        guard FileManager.default.fileExists(atPath: inbox.path) else { return }
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: inbox, includingPropertiesForKeys: nil,
            )
            for file in contents {
                try? FileManager.default.removeItem(at: file)
            }
        } catch {
            AppLog.warning("MainController", "cleanupInbox failed: \(error)")
        }
    }
}
