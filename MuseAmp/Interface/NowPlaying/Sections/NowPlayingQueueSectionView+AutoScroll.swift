import UIKit

extension NowPlayingQueueSectionView {
    func performPendingAutoScrollIfNeeded(animated: Bool) {
        guard hasAppliedInitialSnapshot,
              pendingAutoScrollToQueueStart || needsInitialAutoScrollOnPresent
        else {
            return
        }

        guard bounds.width > 0,
              bounds.height > 0,
              queueTableView.bounds.height > 0,
              window != nil
        else {
            return
        }

        guard !hasActiveProgrammaticScrollBlock() else {
            return
        }

        updateSpacerFramesIfNeeded()
        queueTableView.layoutIfNeeded()
        layoutIfNeeded()

        let targetOffsetY = targetQueueAnchorOffsetY()
        pendingAutoScrollToQueueStart = false
        needsInitialAutoScrollOnPresent = false
        logAutoScroll(
            targetOffsetY: targetOffsetY,
            animated: animated,
        )

        if animated {
            animateScroll(to: targetOffsetY)
        } else {
            setScrollOffset(to: targetOffsetY)
        }
    }

    func targetQueueAnchorOffsetY() -> CGFloat {
        let adjustedTopInset = queueTableView.adjustedContentInset.top
        let historyHeight = CGFloat(queueSnapshot.historyItems.count) * Layout.queueRowHeight
        let controlsTopY = Layout.headerSpacerHeight + historyHeight

        if queueSnapshot.upcomingItems.isEmpty {
            return clampedOffsetY(controlsTopY - adjustedTopInset)
        }

        let currentRowMidY = controlsTopY + Layout.sectionHeaderHeight + (Layout.queueRowHeight / 2)
        let rawOffsetY = currentRowMidY
            - (queueTableView.bounds.height * Layout.activeRowAnchorFraction)
            - adjustedTopInset
        return clampedOffsetY(rawOffsetY)
    }

    func animateScroll(to targetOffsetY: CGFloat) {
        let clampedOffsetY = clampedOffsetY(targetOffsetY)

        Interface.smoothSpringAnimate {
            self.queueTableView.setContentOffset(CGPoint(x: 0, y: clampedOffsetY), animated: false)
            self.layoutIfNeeded()
        }
    }

    func setScrollOffset(to targetOffsetY: CGFloat) {
        let clampedOffsetY = clampedOffsetY(targetOffsetY)
        queueTableView.setContentOffset(CGPoint(x: 0, y: clampedOffsetY), animated: false)
    }

    func blockProgrammaticScroll() {
        let blockedUntil = Date().addingTimeInterval(Layout.programmaticScrollBlockDuration)
        isProgramaticScrollBlocked = blockedUntil
        pendingProgrammaticScrollRetry?.cancel()

        let retryWorkItem = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }

            pendingProgrammaticScrollRetry = nil

            guard isProgramaticScrollBlocked <= Date() else {
                return
            }

            isProgramaticScrollBlocked = .distantPast
            performPendingAutoScrollIfNeeded(animated: true)
        }

        pendingProgrammaticScrollRetry = retryWorkItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Layout.programmaticScrollBlockDuration,
            execute: retryWorkItem,
        )
    }

    func hasActiveProgrammaticScrollBlock() -> Bool {
        if isProgramaticScrollBlocked <= Date() {
            isProgramaticScrollBlocked = .distantPast
            return false
        }
        return true
    }

    func clampedOffsetY(_ offsetY: CGFloat) -> CGFloat {
        let maximumOffsetY = max(
            queueTableView.contentSize.height
                + queueTableView.adjustedContentInset.bottom
                - queueTableView.bounds.height,
            -queueTableView.adjustedContentInset.top,
        )
        return min(max(offsetY, -queueTableView.adjustedContentInset.top), maximumOffsetY)
    }
}
