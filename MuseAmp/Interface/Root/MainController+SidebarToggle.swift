//
//  MainController+SidebarToggle.swift
//  MuseAmp
//
//  Created by @Lakr233 on 2026/10/03.
//

import SnapKit
import UIKit

#if targetEnvironment(macCatalyst)

    // MARK: - Sidebar Toggle (Mac)

    /// UIKit only shows its sidebar button in the sidebar's own navigation
    /// bar, which the Mac layout hides, so a collapsed sidebar could only come
    /// back through the View menu. This toggle sits in the title bar row: at
    /// the sidebar's trailing edge while the sidebar is shown, and right of
    /// the traffic lights while it is collapsed.
    extension MainController {
        private enum SidebarToggleLayout {
            /// Clears the traffic lights with the same gap as a Mac toolbar item.
            static let trafficLightClearance: CGFloat = 100
            /// Gap between the button and the sidebar's trailing edge. The
            /// symbol then sits about as far from that edge as the traffic
            /// lights sit from the window's leading edge.
            static let sidebarEdgeInset: CGFloat = 8
            static let side: CGFloat = 32
            static let symbolPointSize: CGFloat = 17
            /// Full screen has no title bar. A row of the same height takes
            /// its place, so the toggle never covers the navigation bar.
            static let fullScreenRowHeight: CGFloat = 41
        }

        func makeSidebarToggleButton() -> UIButton {
            var configuration = UIButton.Configuration.plain()
            configuration.image = UIImage(systemName: "sidebar.left")
            configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
                pointSize: SidebarToggleLayout.symbolPointSize,
                weight: .regular,
            )
            configuration.baseForegroundColor = .secondaryLabel
            let button = UIButton(configuration: configuration)
            button.preferredBehavioralStyle = .pad
            button.accessibilityIdentifier = "sidebar.toggle"
            button.addAction(
                UIAction { [weak self] _ in
                    self?.toggleSidebarFromButton()
                },
                for: .touchUpInside,
            )
            return button
        }

        func installSidebarToggleButton() {
            guard sidebarToggleButton.superview == nil else { return }

            let titlebarRow = UILayoutGuide()
            view.addLayoutGuide(titlebarRow)
            titlebarRow.snp.makeConstraints { make in
                make.top.equalTo(view.snp.top)
                make.bottom.equalTo(view.safeAreaLayoutGuide.snp.top)
            }

            view.addSubview(sidebarToggleButton)
            sidebarToggleButton.snp.makeConstraints { make in
                make.leading.equalToSuperview().offset(SidebarToggleLayout.trafficLightClearance)
                make.centerY.equalTo(titlebarRow)
                make.size.equalTo(SidebarToggleLayout.side)
            }

            updateSidebarToggleButton(sidebarVisible: rootSplitViewController.isSidebarVisible)
            updateSidebarToggleVisibility()
            updateFullScreenTitlebarRow()
            updateSidebarTogglePosition()
        }

        /// Pins the button's trailing edge to the sidebar's trailing edge:
        /// the sidebar column's edge or where the detail column's safe area
        /// starts, whichever is nearer. Once the sidebar is gone, the
        /// traffic-light clearance wins. Called on every layout, so the
        /// button follows window resizes.
        func updateSidebarTogglePosition() {
            guard sidebarToggleButton.superview != nil,
                  contentContainerController.view.isDescendant(of: view)
            else { return }
            rootSplitViewController.view.layoutIfNeeded()

            let detailContent = contentContainerController.view.safeAreaLayoutGuide.layoutFrame
            let detailLeading = view.convert(detailContent, from: contentContainerController.view).minX
            // macOS 26 starts the detail column's safe area a few points past
            // the sidebar, so the sidebar column's own edge wins when nearer.
            let sidebarColumn: UIView = sidebarViewController.navigationController?.view ?? sidebarViewController.view
            let sidebarColumnTrailing = sidebarColumn.window == nil
                ? detailLeading
                : view.convert(sidebarColumn.bounds, from: sidebarColumn).maxX
            let sidebarTrailing = min(detailLeading, sidebarColumnTrailing)
            let leading = max(
                SidebarToggleLayout.trafficLightClearance,
                sidebarTrailing - SidebarToggleLayout.sidebarEdgeInset - SidebarToggleLayout.side,
            )
            guard abs(sidebarToggleButton.frame.minX - leading) > 0.5 else { return }
            sidebarToggleButton.snp.updateConstraints { make in
                make.leading.equalToSuperview().offset(leading)
            }
        }

        /// Keeps the title bar row in full screen. The detail column then
        /// gives the row back while the sidebar is shown and keeps it while
        /// the sidebar is hidden, exactly as it does with the real title bar.
        func updateFullScreenTitlebarRow() {
            guard currentLayoutMode == .catalyst, let window = view.window else { return }
            let isFullScreen = window.safeAreaInsets.top == 0
            let rowHeight = isFullScreen ? SidebarToggleLayout.fullScreenRowHeight : 0
            guard additionalSafeAreaInsets.top != rowHeight else { return }
            AppLog.Layout.info(self, "updateFullScreenTitlebarRow isFullScreen=\(isFullScreen) rowHeight=\(rowHeight)")
            additionalSafeAreaInsets.top = rowHeight
        }

        /// Now Playing covers the whole window, so the toggle steps aside
        /// while it is open and comes back once it has closed.
        func updateSidebarToggleVisibility() {
            guard sidebarToggleButton.superview != nil else { return }
            let isHidden = isNowPlayingPopupOpen
            guard sidebarToggleButton.isHidden != isHidden else { return }

            sidebarToggleButton.isHidden = isHidden
            guard !isHidden else { return }
            sidebarToggleButton.alpha = 0
            Interface.quickAnimate {
                self.sidebarToggleButton.alpha = 1
            }
        }

        private func updateSidebarToggleButton(sidebarVisible: Bool) {
            let title = sidebarVisible
                ? String(localized: "Hide Sidebar")
                : String(localized: "Show Sidebar")
            sidebarToggleButton.accessibilityLabel = title
            sidebarToggleButton.toolTip = title
        }

        /// Sends the same action as View > Show/Hide Sidebar. A direct
        /// `show(.primary)` / `hide(.primary)` changes the column without
        /// calling the delegate's `willShow` / `willHide`, so the title bar
        /// inset, the popup bar and this button would keep the old layout.
        private func toggleSidebarFromButton() {
            AppLog.Layout.info(self, "sidebar toggle pressed sidebarVisible=\(rootSplitViewController.isSidebarVisible)")
            rootSplitViewController.toggleSidebar(sidebarToggleButton)
        }

        /// Called from the split view delegate's `willShow` / `willHide`,
        /// which run for the toggle and for View > Show/Hide Sidebar alike, so
        /// the button always names the action the menu item would perform.
        func sidebarToggleWillChange(sidebarVisible: Bool) {
            updateSidebarToggleButton(sidebarVisible: sidebarVisible)
            animateSidebarToggleAlongsideColumnTransition()
        }

        /// The button's position comes from the detail column's layout, so
        /// laying out alongside the column transition moves it with the
        /// sidebar instead of jumping once the transition ends.
        private func animateSidebarToggleAlongsideColumnTransition() {
            guard sidebarToggleButton.superview != nil else { return }
            let relayout: () -> Void = { [weak self] in
                guard let self else { return }
                updateSidebarTogglePosition()
                view.layoutIfNeeded()
            }
            let animatesAlongside = rootSplitViewController.transitionCoordinator?.animate(
                alongsideTransition: { _ in relayout() },
                completion: { _ in relayout() },
            ) ?? false
            guard !animatesAlongside else { return }
            DispatchQueue.main.async {
                Interface.springAnimate(animations: relayout)
            }
        }
    }

#endif
