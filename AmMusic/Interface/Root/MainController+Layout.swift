//
//  MainController+Layout.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import SnapKit
import UIKit

// MARK: - Layout Installation

extension MainController {
    // MARK: - Compact Layout

    func installCompactLayout() {
        guard compactTabBarController.parent == nil else { return }

        addChild(compactTabBarController)
        view.addSubview(compactTabBarController.view)
        compactTabBarController.view.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        compactTabBarController.didMove(toParent: self)
    }

    func teardownCompactLayout() {
        guard compactTabBarController.parent != nil else { return }
        compactTabBarController.willMove(toParent: nil)
        compactTabBarController.view.removeFromSuperview()
        compactTabBarController.removeFromParent()
    }

    // MARK: - Relaxed Layout (UISplitViewController)

    func installRelaxedLayout() {
        guard rootSplitViewController.parent == nil else { return }

        rootSplitViewController.preferredDisplayMode = .oneBesideSecondary
        rootSplitViewController.preferredSplitBehavior = .tile
        rootSplitViewController.primaryBackgroundStyle = .sidebar
        rootSplitViewController.preferredPrimaryColumnWidthFraction = 0.22
        rootSplitViewController.minimumPrimaryColumnWidth = 180
        rootSplitViewController.maximumPrimaryColumnWidth = 320
        rootSplitViewController.presentsWithGesture = true
        rootSplitViewController.delegate = self

        rootSplitViewController.setViewController(sidebarViewController, for: .primary)

        let nav: UINavigationController = if let selectedPlaylistID {
            playlistNavigationController(for: selectedPlaylistID)
        } else {
            contentNavigationController(for: selectedDestination)
        }
        installContentNavigationController(nav)
        navigationCoordinator.rootViewController = nav
        contentContainerController.view.tintColor = .accent
        rootSplitViewController.setViewController(contentContainerController, for: .secondary)

        addChild(rootSplitViewController)
        view.addSubview(rootSplitViewController.view)
        rootSplitViewController.view.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        rootSplitViewController.didMove(toParent: self)
    }

    func installCatalystLayout() {
        installRelaxedLayout()
        rootSplitViewController.preferredDisplayMode = .oneBesideSecondary
        rootSplitViewController.preferredSplitBehavior = .tile
        rootSplitViewController.presentsWithGesture = false

        // Hide the sidebar toggle button so the sidebar stays always visible.
        rootSplitViewController.navigationItem.leftBarButtonItem = nil
        sidebarViewController.navigationItem.leftBarButtonItem = nil
        rootSplitViewController.displayModeButtonVisibility = .never
    }

    func teardownRelaxedLayout() {
        unbindPlaybackPopup()

        if let activeNav = activeContentNavigationController {
            activeNav.willMove(toParent: nil)
            activeNav.view.removeFromSuperview()
            activeNav.removeFromParent()
        }

        guard rootSplitViewController.parent != nil else { return }
        rootSplitViewController.willMove(toParent: nil)
        rootSplitViewController.view.removeFromSuperview()
        rootSplitViewController.removeFromParent()
    }

    // MARK: - Content Installation

    func installContentNavigationController(_ nav: UINavigationController) {
        if let current = contentContainerController.children.first, current !== nav {
            current.willMove(toParent: nil)
            current.view.removeFromSuperview()
            current.removeFromParent()
        }

        guard nav.parent == nil else { return }

        contentContainerController.addChild(nav)
        contentContainerController.view.addSubview(nav.view)
        nav.view.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        nav.didMove(toParent: contentContainerController)
    }
}

// MARK: - UISplitViewControllerDelegate

extension MainController: UISplitViewControllerDelegate {
    func splitViewController(
        _: UISplitViewController,
        topColumnForCollapsingToProposedTopColumn _: UISplitViewController.Column,
    ) -> UISplitViewController.Column {
        .primary
    }

    func splitViewController(
        _: UISplitViewController,
        displayModeForExpandingToProposedDisplayMode proposedDisplayMode: UISplitViewController.DisplayMode,
    ) -> UISplitViewController.DisplayMode {
        proposedDisplayMode
    }
}
