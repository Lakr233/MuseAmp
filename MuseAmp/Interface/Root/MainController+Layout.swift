//
//  MainController+Layout.swift
//  MuseAmp
//
//  Created by @Lakr233 on 2026/04/11.
//

import LNPopupController
import SnapKit
import UIKit

// MARK: - Layout Installation

extension MainController {
    // MARK: - Compact Layout

    func installCompactLayout() {
        guard compactTabBarController.parent == nil else { return }

        AppLog.Layout.info(self, "installCompactLayout")
        addChild(compactTabBarController)
        view.addSubview(compactTabBarController.view)
        compactTabBarController.view.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        compactTabBarController.didMove(toParent: self)
    }

    /// Detaches the tab shell but keeps it, so its tabs and navigation stacks
    /// survive a size-class round trip. Detaching releases its Now Playing;
    /// the next install rebuilds it.
    func teardownCompactLayout() {
        guard let compactTabBarController = compactTabBarControllerIfLoaded,
              compactTabBarController.parent != nil
        else { return }
        AppLog.Layout.info(self, "teardownCompactLayout")
        compactTabBarController.willMove(toParent: nil)
        compactTabBarController.view.removeFromSuperview()
        compactTabBarController.removeFromParent()
    }

    // MARK: - Relaxed Layout (UISplitViewController)

    func installRelaxedLayout() {
        guard rootSplitViewController.parent == nil else { return }

        AppLog.Layout.info(self, "installRelaxedLayout selectedPlaylistID=\(selectedPlaylistID?.uuidString ?? "nil")")
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
        AppLog.Layout.info(self, "installCatalystLayout applying Catalyst overrides")
        rootSplitViewController.preferredDisplayMode = .oneBesideSecondary
        rootSplitViewController.preferredSplitBehavior = .tile
        rootSplitViewController.presentsWithGesture = false

        // Hide the sidebar toggle button so the sidebar stays always visible.
        rootSplitViewController.navigationItem.leftBarButtonItem = nil
        sidebarViewController.navigationItem.leftBarButtonItem = nil
        rootSplitViewController.displayModeButtonVisibility = .never

        #if targetEnvironment(macCatalyst)
            updateDetailColumnTitlebarInset()
        #endif
    }

    #if targetEnvironment(macCatalyst)
        /// The hidden title bar still reserves its height as a top safe-area
        /// inset. While the sidebar is shown it sits under the traffic
        /// lights, so the detail column gives the inset back and its
        /// navigation bar sits in the traffic-light row instead of under an
        /// empty band. With the sidebar hidden (View > Hide Sidebar) the
        /// detail column keeps the inset, so its back button clears the
        /// traffic lights.
        func updateDetailColumnTitlebarInset(sidebarVisible: Bool? = nil) {
            guard currentLayoutMode == .catalyst else { return }
            let sidebarVisible = sidebarVisible ?? rootSplitViewController.isSidebarVisible
            let titlebarHeight = sidebarVisible ? view.safeAreaInsets.top : 0
            let insets = UIEdgeInsets(top: -titlebarHeight, left: 0, bottom: 0, right: 0)
            guard contentContainerController.additionalSafeAreaInsets != insets else { return }
            contentContainerController.additionalSafeAreaInsets = insets
            relayoutDetailNavigationControllers()
        }

        /// When the inset shrinks and no size changes, UINavigationController
        /// moves its bar up in the next layout pass but leaves its top view
        /// controller's safe area at the old, taller value, so the content
        /// sits a titlebar height below the bar. A second pass, with the bar
        /// already in place, corrects it.
        private func relayoutDetailNavigationControllers() {
            contentContainerController.view.layoutIfNeeded()
            for child in contentContainerController.children {
                child.view.setNeedsLayout()
                child.view.layoutIfNeeded()
            }
        }

        private func animateDetailColumnTitlebarInset(sidebarVisible: Bool) {
            let queued = rootSplitViewController.transitionCoordinator?.animate(alongsideTransition: { [weak self] _ in
                self?.updateDetailColumnTitlebarInset(sidebarVisible: sidebarVisible)
            }) ?? false
            guard !queued else { return }
            updateDetailColumnTitlebarInset(sidebarVisible: sidebarVisible)
        }
    #endif

    func teardownRelaxedLayout() {
        AppLog.Layout.info(self, "teardownRelaxedLayout")
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

    func splitViewController(
        _: UISplitViewController,
        willShow column: UISplitViewController.Column,
    ) {
        guard column == .primary else { return }
        rootSplitViewController.animatePopupBarToCurrentLayout(sidebarWillBeVisible: true)
        #if targetEnvironment(macCatalyst)
            animateDetailColumnTitlebarInset(sidebarVisible: true)
        #endif
    }

    func splitViewController(
        _: UISplitViewController,
        willHide column: UISplitViewController.Column,
    ) {
        guard column == .primary else { return }
        rootSplitViewController.animatePopupBarToCurrentLayout(sidebarWillBeVisible: false)
        #if targetEnvironment(macCatalyst)
            animateDetailColumnTitlebarInset(sidebarVisible: false)
        #endif
    }
}
