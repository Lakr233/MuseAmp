//
//  TabBarController.swift
//  MuseAmp
//
//  Created by @Lakr233 on 2026/04/11.
//

import Combine
import LNPopupController
import SwifterSwift
import Then
import UIKit

class TabBarController: UITabBarController {
    let environment: AppEnvironment
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
    var nowPlayingPopupContentViewController: NowPlayingCompactController?
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
    lazy var popupLyricsReloadPresenter = LyricsReloadPresenter(
        reloadService: environment.lyricsReloadService,
        viewController: self,
    )
    lazy var popupSongContextMenuProvider = SongContextMenuProvider(
        playlistMenuProvider: popupPlaylistMenuProvider,
        lyricsReloadPresenter: popupLyricsReloadPresenter,
    )

    private enum Accessibility {
        static let tabBar = "main.tabbar"
    }

    init(environment: AppEnvironment) {
        self.environment = environment
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tabBar.accessibilityIdentifier = Accessibility.tabBar
        delegate = self
        popupPresentationDelegate = self
        popupInteractionStyle = .drag

        if #available(iOS 18.0, *) {
            setupWithUITab()
        } else {
            setupWithViewControllers()
        }

        configurePopupBar()
        bindDownloadsBadge()
        bindPlaybackPopup()
        observeServerConfigurationChanges()
    }

    override var childForStatusBarHidden: UIViewController? {
        if isNowPlayingPopupOpen,
           let nowPlayingPopupContentViewController
        {
            return nowPlayingPopupContentViewController
        }

        return selectedViewController
    }

    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation {
        .fade
    }

    // MARK: - iOS 18+ (UITab, Liquid Glass on iOS 26)

    @available(iOS 18.0, *)
    private func setupWithUITab() {
        let albumsTab = UITab(
            title: String(localized: "Albums"),
            image: UIImage(systemName: "square.stack"),
            identifier: "albums",
        ) { [environment] _ in
            let vc = SongLibraryViewController(environment: environment)
            vc.title = String(localized: "Albums")
            return UINavigationController(rootViewController: vc).then {
                $0.navigationBar.prefersLargeTitles = true
                $0.navigationBar.accessibilityIdentifier = "nav.albums"
            }
        }

        let songsTab = UITab(
            title: String(localized: "Songs"),
            image: UIImage(systemName: "music.note"),
            identifier: "songs",
        ) { [environment] _ in
            let vc = SongsViewController(environment: environment)
            vc.title = String(localized: "Songs")
            return UINavigationController(rootViewController: vc).then {
                $0.navigationBar.prefersLargeTitles = true
                $0.navigationBar.accessibilityIdentifier = "nav.songs"
            }
        }

        let playlistTab = UITab(
            title: String(localized: "Playlist"),
            image: UIImage(systemName: "music.note.list"),
            identifier: "playlist",
        ) { [environment] _ in
            let vc = PlaylistViewController(environment: environment)
            vc.title = String(localized: "Playlist")
            return UINavigationController(rootViewController: vc).then {
                $0.navigationBar.prefersLargeTitles = true
                $0.navigationBar.accessibilityIdentifier = "nav.playlist"
            }
        }

        let settingsTab = UITab(
            title: String(localized: "Settings"),
            image: UIImage(systemName: "gearshape"),
            identifier: "settings",
        ) { [environment] _ in
            let vc = SettingsViewController(environment: environment)
            vc.title = String(localized: "Settings")
            return UINavigationController(rootViewController: vc).then {
                $0.navigationBar.prefersLargeTitles = true
                $0.navigationBar.accessibilityIdentifier = "nav.settings"
            }
        }

        let searchTab: UISearchTab? = AppPreferences.currentSubsonicConfiguration != nil
            ? UISearchTab { [environment] _ in
                let vc = SearchViewController(environment: environment)
                vc.title = String(localized: "Search")
                return UINavigationController(rootViewController: vc).then {
                    $0.navigationBar.prefersLargeTitles = false
                    $0.navigationBar.accessibilityIdentifier = "nav.search"
                }
            }
            : nil

        if #available(iOS 26.0, *) {
            var built = [albumsTab, songsTab, playlistTab, settingsTab]
            if let searchTab {
                built.append(searchTab)
            }
            tabs = built
            return
        }

        var built = [albumsTab, songsTab, playlistTab]
        if let searchTab {
            built.append(searchTab)
        }
        built.append(settingsTab)
        tabs = built
    }

    // MARK: - iOS 16–17 (legacy viewControllers)

    private func setupWithViewControllers() {
        var navTabs: [(UIViewController, String, String, String)] = [
            (SongLibraryViewController(environment: environment), String(localized: "Albums"), "square.stack", "albums"),
            (SongsViewController(environment: environment), String(localized: "Songs"), "music.note", "songs"),
            (PlaylistViewController(environment: environment), String(localized: "Playlist"), "music.note.list", "playlist"),
        ]
        if AppPreferences.currentSubsonicConfiguration != nil {
            navTabs.append((SearchViewController(environment: environment), String(localized: "Search"), "magnifyingglass", "search"))
        }
        navTabs.append((SettingsViewController(environment: environment), String(localized: "Settings"), "gearshape", "settings"))

        let navControllers = navTabs.map { vc, title, icon, identifier in
            vc.title = title
            vc.tabBarItem = UITabBarItem(
                title: title,
                image: UIImage(systemName: icon),
                selectedImage: nil,
            )
            return UINavigationController(rootViewController: vc).then {
                $0.navigationBar.prefersLargeTitles = true
                $0.navigationBar.accessibilityIdentifier = "nav.\(identifier)"
                $0.tabBarItem.accessibilityIdentifier = "tab.\(identifier)"
            }
        }

        viewControllers = navControllers
    }

    private func bindDownloadsBadge() {
        environment.downloadManager.tasksPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] tasks in
                self?.updateDownloadsBadge(count: tasks.count)
            }
            .store(in: &cancellables)
    }

    private func updateDownloadsBadge(count: Int) {
        let settingsTitle = String(localized: "Settings")
        guard let item = tabBar.items?.first(where: { $0.title == settingsTitle }) else {
            return
        }
        item.badgeValue = count > 0 ? String(count) : nil
    }

    // MARK: - Server Configuration

    private func observeServerConfigurationChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleServerConfigurationDidChange),
            name: .serverConfigurationDidChange,
            object: nil,
        )
    }

    @objc private func handleServerConfigurationDidChange() {
        let shouldShow = AppPreferences.currentSubsonicConfiguration != nil

        if #available(iOS 18.0, *) {
            let currentTabs = tabs
            let hasSearch = currentTabs.contains(where: { $0 is UISearchTab })
            guard shouldShow != hasSearch else { return }

            if shouldShow {
                let searchTab = UISearchTab { [environment] _ in
                    let vc = SearchViewController(environment: environment)
                    vc.title = String(localized: "Search")
                    return UINavigationController(rootViewController: vc).then {
                        $0.navigationBar.prefersLargeTitles = false
                        $0.navigationBar.accessibilityIdentifier = "nav.search"
                    }
                }
                if #available(iOS 26.0, *) {
                    tabs = currentTabs + [searchTab]
                } else {
                    guard let settingsIndex = currentTabs.firstIndex(where: { $0.identifier == "settings" }) else { return }
                    var updated = currentTabs
                    updated.insert(searchTab, at: settingsIndex)
                    tabs = updated
                }
            } else {
                tabs = currentTabs.filter { !($0 is UISearchTab) }
            }
        } else {
            let currentVCs = viewControllers ?? []
            let hasSearch = currentVCs.contains { vc in
                guard let nav = vc as? UINavigationController, let first = nav.viewControllers.first else { return false }
                return first is SearchViewController
            }
            guard shouldShow != hasSearch else { return }

            if shouldShow {
                let searchVC = SearchViewController(environment: environment)
                searchVC.title = String(localized: "Search")
                searchVC.tabBarItem = UITabBarItem(
                    title: String(localized: "Search"),
                    image: UIImage(systemName: "magnifyingglass"),
                    selectedImage: nil,
                )
                let searchNav = UINavigationController(rootViewController: searchVC).then {
                    $0.navigationBar.prefersLargeTitles = true
                    $0.navigationBar.accessibilityIdentifier = "nav.search"
                    $0.tabBarItem.accessibilityIdentifier = "tab.search"
                }
                guard let settingsIndex = currentVCs.firstIndex(where: { vc in
                    guard let nav = vc as? UINavigationController, let first = nav.viewControllers.first else { return false }
                    return first is SettingsViewController
                }) else { return }
                var updated = currentVCs
                updated.insert(searchNav, at: settingsIndex)
                viewControllers = updated
            } else {
                viewControllers = currentVCs.filter { vc in
                    guard let nav = vc as? UINavigationController, let first = nav.viewControllers.first else { return true }
                    return !(first is SearchViewController)
                }
            }
        }
    }
}
