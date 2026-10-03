import LNPopupController
import UIKit

/// Hosts the relaxed and Catalyst popup bar. LNPopupController keeps the bar
/// frame at the full container width, so the open popup covers the whole
/// window; the bar's margins place the floating bar in the secondary column,
/// three fifths of its width and centred.
final class PopupBarSplitViewController: UISplitViewController {
    private enum SidebarLayout {
        case live
        case pinned(sidebarVisible: Bool)
    }

    /// Pinned from `willShow` / `willHide` until the bar animation ends,
    /// because `displayMode` still describes the old state while the
    /// transition lays out.
    private var sidebarLayout: SidebarLayout = .live
    private var sidebarLayoutGeneration = 0

    var isSidebarVisible: Bool {
        displayMode == .oneBesideSecondary || displayMode == .oneOverSecondary
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        _ = Self.isPopupBarMarginsHookAvailable
        // The margins override already keeps the bar out of the sidebar; this
        // also keeps the sidebar's children from reserving room for the bar.
        popupBarAvoidsPrimaryColumn = true
    }

    /// Moves the popup bar toward its layout for the sidebar's upcoming
    /// visibility, alongside the column transition when there is one.
    func animatePopupBarToCurrentLayout(sidebarWillBeVisible: Bool) {
        guard popupPresentationState != .barHidden else { return }
        sidebarLayout = .pinned(sidebarVisible: sidebarWillBeVisible)
        sidebarLayoutGeneration += 1
        let generation = sidebarLayoutGeneration

        let relayout: () -> Void = { [weak self] in
            guard let self else { return }
            view.setNeedsLayout()
            view.layoutIfNeeded()
            popupBar.layoutIfNeeded()
        }
        // A cancelled interactive transition leaves the sidebar where it was,
        // so the bar animates back to the live layout.
        let finish: (_ cancelled: Bool) -> Void = { [weak self] cancelled in
            guard let self, sidebarLayoutGeneration == generation else { return }
            sidebarLayout = .live
            guard cancelled else {
                view.setNeedsLayout()
                return
            }
            Interface.springAnimate(animations: relayout)
        }

        let animatesAlongside = transitionCoordinator?.animate(
            alongsideTransition: { _ in relayout() },
            completion: { context in finish(context.isCancelled) },
        ) ?? false
        guard !animatesAlongside else { return }
        DispatchQueue.main.async {
            Interface.springAnimate(animations: relayout) { _ in finish(false) }
        }
    }

    /// Margins that leave three fifths of the secondary column for the bar,
    /// centred in that column.
    static func popupBarMargins(
        containerWidth: CGFloat,
        sidebarWidth: CGFloat,
        primaryEdge: UISplitViewController.PrimaryEdge,
    ) -> NSDirectionalEdgeInsets {
        guard containerWidth > 0 else { return .zero }
        let sideGap = (containerWidth - sidebarWidth) / 5
        let sidebarSide = sidebarWidth + sideGap
        guard primaryEdge == .leading else {
            return NSDirectionalEdgeInsets(top: 0, leading: sideGap, bottom: 0, trailing: sidebarSide)
        }
        return NSDirectionalEdgeInsets(top: 0, leading: sidebarSide, bottom: 0, trailing: sideGap)
    }

    private var isSidebarVisibleForPopupBar: Bool {
        switch sidebarLayout {
        case let .pinned(sidebarVisible): sidebarVisible
        case .live: isSidebarVisible
        }
    }
}

// MARK: - LNPopupController Margins Hook

extension PopupBarSplitViewController {
    /// Private LNPopupController selector that `UISplitViewController`
    /// implements and calls on every popup bar layout pass.
    static let popupBarMarginsSelector = NSSelectorFromString("_ln_popupBarMarginsForPopupBar:")
    /// Private `LNPopupBar` property that stores and applies those margins.
    static let popupBarAppliedMarginsSelector = NSSelectorFromString("_hackyMarginsInSuperviewSemanticContext")

    /// Checked once; when LNPopupController renames the hook, the bar falls
    /// back to its own sidebar-avoiding layout and this logs why.
    static let isPopupBarMarginsHookAvailable: Bool = {
        let hasMarginsHook = UISplitViewController.instancesRespond(to: popupBarMarginsSelector)
        let hasAppliedMargins = LNPopupBar.instancesRespond(to: popupBarAppliedMarginsSelector)
        guard hasMarginsHook, hasAppliedMargins else {
            AppLog.Layout.error(
                PopupBarSplitViewController.self,
                "LNPopupController popup bar margins hook missing marginsHook=\(hasMarginsHook) appliedMargins=\(hasAppliedMargins); the split view popup bar falls back to the LNPopupController layout",
            )
            return false
        }
        return true
    }()

    /// Overrides `-[UISplitViewController _ln_popupBarMarginsForPopupBar:]`
    /// for this class only, replacing LNPopupController's sidebar inset.
    @objc(_ln_popupBarMarginsForPopupBar:)
    func popupBarMargins(for _: LNPopupBar) -> NSDirectionalEdgeInsets {
        Self.popupBarMargins(
            containerWidth: view.bounds.width,
            sidebarWidth: isSidebarVisibleForPopupBar ? primaryColumnWidth : 0,
            primaryEdge: primaryEdge,
        )
    }
}
