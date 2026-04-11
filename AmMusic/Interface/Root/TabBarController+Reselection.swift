//
//  TabBarController+Reselection.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import UIKit

protocol TabBarReselectScrollable: AnyObject {
    var primaryScrollViewForTabReselection: UIScrollView? { get }
}

extension TabBarController {
    func handleReselection(of viewController: UIViewController, animated: Bool) {
        if let navigationController = viewController as? UINavigationController {
            handleNavigationReselection(of: navigationController, animated: animated)
            return
        }

        scrollPrimaryScrollViewToTop(in: viewController, animated: animated)
    }

    func handleNavigationReselection(of navigationController: UINavigationController, animated: Bool) {
        let targetViewController = navigationController.viewControllers.first ?? navigationController
        targetViewController.loadViewIfNeeded()

        let scrollToTop = { [weak self, weak targetViewController] in
            guard let self, let targetViewController else { return }
            scrollPrimaryScrollViewToTop(in: targetViewController, animated: animated)
        }

        guard navigationController.viewControllers.count > 1 else {
            scrollToTop()
            return
        }

        if animated {
            navigationController.popToRootViewController(animated: true)
            if let coordinator = navigationController.transitionCoordinator {
                coordinator.animate(alongsideTransition: nil) { _ in
                    scrollToTop()
                }
            } else {
                scrollToTop()
            }
            return
        }

        navigationController.popToRootViewController(animated: false)
        scrollToTop()
    }

    func scrollPrimaryScrollViewToTop(in viewController: UIViewController, animated: Bool) {
        guard let scrollView = preferredScrollView(in: viewController) else {
            return
        }

        let targetOffset = CGPoint(
            x: scrollView.contentOffset.x,
            y: -scrollView.adjustedContentInset.top,
        )

        guard abs(scrollView.contentOffset.y - targetOffset.y) > 0.5 else {
            return
        }

        scrollView.setContentOffset(targetOffset, animated: animated)
    }

    func preferredScrollView(in viewController: UIViewController) -> UIScrollView? {
        viewController.loadViewIfNeeded()

        if let provider = viewController as? TabBarReselectScrollable,
           let scrollView = provider.primaryScrollViewForTabReselection,
           isEligiblePrimaryScrollView(scrollView)
        {
            return scrollView
        }

        let childCandidates = viewController.children
            .reversed()
            .compactMap { preferredScrollView(in: $0) }
        if let childScrollView = prioritizedScrollView(from: childCandidates) {
            return childScrollView
        }

        return prioritizedScrollView(from: collectScrollViews(in: viewController.view))
    }

    private func prioritizedScrollView(from scrollViews: [UIScrollView]) -> UIScrollView? {
        scrollViews
            .filter(isEligiblePrimaryScrollView)
            .max { lhs, rhs in
                primaryScrollViewScore(for: lhs) < primaryScrollViewScore(for: rhs)
            }
    }

    private func collectScrollViews(in view: UIView) -> [UIScrollView] {
        var scrollViews: [UIScrollView] = []

        if let scrollView = view as? UIScrollView {
            scrollViews.append(scrollView)
        }

        for subview in view.subviews {
            scrollViews.append(contentsOf: collectScrollViews(in: subview))
        }

        return scrollViews
    }

    private func isEligiblePrimaryScrollView(_ scrollView: UIScrollView) -> Bool {
        guard scrollView.window != nil || scrollView.superview != nil else {
            return false
        }

        guard !scrollView.isHidden,
              scrollView.alpha > 0.01,
              scrollView.bounds.width > 0,
              scrollView.bounds.height > 0
        else {
            return false
        }

        return true
    }

    private func primaryScrollViewScore(for scrollView: UIScrollView) -> CGFloat {
        let visibleArea = scrollView.bounds.width * scrollView.bounds.height
        return visibleArea + (scrollView.scrollsToTop ? 1_000_000 : 0)
    }
}

extension TabBarController: UITabBarControllerDelegate {
    func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
        guard tabBarController.selectedViewController === viewController else {
            return true
        }

        handleReselection(of: viewController, animated: true)
        return false
    }
}
