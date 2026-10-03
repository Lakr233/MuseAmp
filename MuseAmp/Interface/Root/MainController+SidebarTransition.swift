//
//  MainController+SidebarTransition.swift
//  MuseAmp
//
//  Created by @Lakr233 on 2026/10/03.
//

import UIKit

#if targetEnvironment(macCatalyst)

    // MARK: - Detail Column During a Sidebar Transition (Mac)

    /// While the sidebar shows or hides, the detail column moves sideways
    /// with the column transition and moves between the traffic-light row
    /// and the row below it. UIKit puts the bar's leading items (the back
    /// button and any left items) at their new place in one frame, so they
    /// are moved back and slide from there.
    ///
    /// The leading items take an L-shaped path so they never cross the
    /// traffic lights or the title bar row's other controls: when the
    /// sidebar hides, the bar drops first and the items then slide left in
    /// the row below; when it shows, the items slide right first and the bar
    /// then rises. The bar, its title and the content share the vertical
    /// leg, so the items stay in their bar throughout.
    extension MainController {
        private enum SidebarTransitionTiming {
            static let legDuration: TimeInterval = 0.21
            /// The second leg starts once the first has carried the items
            /// clear of the title bar row (hide) or past it (show). An
            /// ease-in-out leg is 93% done by then.
            static let secondLegDelay: TimeInterval = 0.163
            /// Legs keep their own timing inside the column transition.
            static let options: UIView.AnimationOptions = [
                .overrideInheritedDuration,
                .overrideInheritedCurve,
                .curveEaseInOut,
            ]
        }

        func animateDetailColumnWithSidebar(sidebarVisible: Bool) {
            guard let coordinator = rootSplitViewController.transitionCoordinator else {
                updateDetailColumnTitlebarInset(sidebarVisible: sidebarVisible)
                return
            }

            let navigationBar = activeContentNavigationController?.navigationBar
            let barControls = navigationBar.map(Self.barItemControls(in:)) ?? []
            let startFrames = barControls.map { $0.convert($0.bounds, to: navigationBar) }
            let verticalLegDelay = sidebarVisible ? SidebarTransitionTiming.secondLegDelay : 0
            let horizontalLegDelay = sidebarVisible ? 0 : SidebarTransitionTiming.secondLegDelay

            coordinator.animate(alongsideTransition: { [weak self] _ in
                guard let self else { return }
                // Lays the columns out with the transition first, so the title
                // and the content move sideways with the sidebar.
                rootSplitViewController.view.layoutIfNeeded()

                Interface.animate(
                    duration: SidebarTransitionTiming.legDuration,
                    delay: verticalLegDelay,
                    options: SidebarTransitionTiming.options,
                ) {
                    self.updateDetailColumnTitlebarInset(sidebarVisible: sidebarVisible)
                }

                guard let navigationBar else { return }
                for (control, start) in zip(barControls, startFrames) {
                    let end = control.convert(control.bounds, to: navigationBar)
                    let offset = start.minX - end.minX
                    guard abs(offset) > 0.5 else { continue }
                    UIView.performWithoutAnimation {
                        control.transform = CGAffineTransform(translationX: offset, y: 0)
                    }
                    Interface.animate(
                        duration: SidebarTransitionTiming.legDuration,
                        delay: horizontalLegDelay,
                        options: SidebarTransitionTiming.options,
                    ) {
                        control.transform = .identity
                    }
                }
            })
        }

        /// The bar's outermost visible controls other than its title, which
        /// UIKit already moves with the transition. Of these, the column
        /// transition moves only the leading items sideways, so only they get
        /// the slide.
        private static func barItemControls(in navigationBar: UINavigationBar) -> [UIView] {
            let topItem = navigationBar.topItem
            func showsTitle(_ view: UIView) -> Bool {
                if let titleView = topItem?.titleView, titleView.isDescendant(of: view) {
                    return true
                }
                if let label = view as? UILabel, let title = topItem?.title, label.text == title {
                    return true
                }
                return view.subviews.contains(where: showsTitle)
            }

            var controls: [UIView] = []
            func collect(in view: UIView) {
                for subview in view.subviews where !subview.isHidden && subview.alpha > 0.01 {
                    guard subview is UIControl else {
                        collect(in: subview)
                        continue
                    }
                    if !showsTitle(subview) {
                        controls.append(subview)
                    }
                }
            }
            collect(in: navigationBar)
            return controls
        }
    }

#endif
