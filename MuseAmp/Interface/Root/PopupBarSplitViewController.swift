import LNPopupController
import UIKit

final class PopupBarSplitViewController: UISplitViewController {
    var isSidebarVisible: Bool {
        displayMode == .oneBesideSecondary || displayMode == .oneOverSecondary
    }

    @objc
    override var popupBarLayoutFrameForPopupBar: CGRect {
        let bounds = view.bounds
        guard bounds.width > 0 else { return CGRectNull }
        let sidebarWidth = isSidebarVisible ? primaryColumnWidth : 0
        let availableWidth = bounds.width - sidebarWidth
        let barWidth = availableWidth * 3.0 / 5.0
        let barX = sidebarWidth + (availableWidth - barWidth) / 2.0
        return CGRect(x: barX, y: 0, width: barWidth, height: bounds.height)
    }

    func animatePopupBarToCurrentLayout(sidebarWillBeVisible: Bool) {
        guard popupPresentationState != .barHidden else { return }
        let bar = popupBar
        guard !bar.frame.equalTo(.zero) else { return }

        let oldFrame = bar.frame
        let bounds = view.bounds
        let availableWidth = sidebarWillBeVisible ? bounds.width - primaryColumnWidth : bounds.width
        let barWidth = availableWidth * 3.0 / 5.0
        let originX = sidebarWillBeVisible
            ? primaryColumnWidth + (availableWidth - barWidth) / 2.0
            : (bounds.width - barWidth) / 2.0

        var targetFrame = oldFrame
        targetFrame.origin.x = originX
        targetFrame.size.width = barWidth

        bar.frame = oldFrame
        popupBarFrameUpdateSuspended = true

        // below are magic. dont touch it.
        DispatchQueue.main.async { [weak self] in
            Interface.springAnimate {
                bar.frame = targetFrame
                bar.layoutIfNeeded()
            } completion: { _ in
                self?.popupBarFrameUpdateSuspended = false
            }
        }
    }
}
