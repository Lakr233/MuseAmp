//
//  LyricTimelineView+Synced.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import UIKit

// MARK: - Synced mode

extension LyricTimelineView {
    func performInitialSyncedReveal(
        with timeline: LRCLyricsTimeline,
        currentTime: TimeInterval,
        fadingOutMessage: Bool,
    ) {
        shouldAnimateNextSyncedReveal = false

        if fadingOutMessage {
            messageLabel.isHidden = false
            messageLabel.alpha = 1
        } else {
            messageLabel.alpha = 1
            messageLabel.isHidden = true
        }

        setVisibleCellsAlpha(0)
        layoutIfNeeded()

        updateSyncedProgress(
            with: timeline,
            currentTime: currentTime,
            animated: false,
            scrollAnimated: false,
        )

        layoutIfNeeded()
        animateInitialRevealCellVisibility(fadingOutMessage: fadingOutMessage)
    }

    func updateSyncedProgress(
        with timeline: LRCLyricsTimeline,
        currentTime: TimeInterval,
        animated: Bool,
        scrollAnimated: Bool = true,
    ) {
        let progress = timeline.progress(at: currentTime)
        let nextActiveIndex = progress?.index
        let previousActiveIndex = activeIndex
        let didActiveIndexChange = nextActiveIndex != previousActiveIndex
        let shouldScrollToTop = nextActiveIndex == nil && previousActiveIndex != nil

        guard didActiveIndexChange || pendingAutoScrollToActiveLine || shouldScrollToTop else {
            return
        }

        if didActiveIndexChange {
            logLyricSwitch(
                from: previousActiveIndex,
                to: nextActiveIndex,
                timeline: timeline,
                currentTime: currentTime,
            )
            applySyncedLineStateChanges(
                from: previousActiveIndex,
                to: nextActiveIndex,
                animated: animated,
            )
        }

        defer { activeIndex = nextActiveIndex }

        guard let nextActiveIndex else {
            if shouldSuspendAutoScroll {
                pendingAutoScrollToActiveLine = shouldScrollToTop
                return
            }
            pendingAutoScrollToActiveLine = false
            if shouldScrollToTop {
                animateScroll(to: -tableView.contentInset.top)
            } else if previousActiveIndex == nil, tableView.numberOfRows(inSection: 0) > 0 {
                let firstLineOffset = targetOffsetY(forRow: 0)
                setScrollOffset(to: firstLineOffset)
            }
            return
        }

        let targetOffsetY = targetOffsetY(forRow: nextActiveIndex)

        if shouldSuspendAutoScroll {
            pendingAutoScrollToActiveLine = true
            return
        }

        pendingAutoScrollToActiveLine = false

        if scrollAnimated {
            animateScroll(to: targetOffsetY)
        } else {
            setScrollOffset(to: targetOffsetY)
        }
    }

    func targetOffsetY(forRow row: Int) -> CGFloat {
        layoutIfNeeded()

        let cellRect = tableView.rectForRow(at: IndexPath(row: row, section: 0))
        let targetCenterY = cellRect.midY
        let rawOffsetY = targetCenterY - (tableView.bounds.height * Layout.activeLineAnchorFraction)
        let maximumOffsetY = max(
            tableView.contentSize.height + tableView.contentInset.bottom - tableView.bounds.height,
            -tableView.contentInset.top,
        )
        let minimumOffsetY = -tableView.contentInset.top

        return min(max(rawOffsetY, minimumOffsetY), maximumOffsetY)
    }

    // MARK: - Line state changes

    func applySyncedLineStateChanges(from previousActiveIndex: Int?, to nextActiveIndex: Int?, animated: Bool) {
        guard let changedRange = changedLineRange(from: previousActiveIndex, to: nextActiveIndex) else {
            return
        }

        let updates = {
            for index in changedRange {
                let indexPath = IndexPath(row: index, section: 0)
                guard let cell = self.tableView.cellForRow(at: indexPath) as? LyricTimelineCell else {
                    continue
                }
                let state = self.stateForLine(at: index, activeIndex: nextActiveIndex)
                cell.applyState(state)
            }
            self.layoutIfNeeded()
        }

        guard animated, !isAnimationSuspended else {
            updates()
            return
        }

        Interface.smoothSpringAnimate(animations: updates)
    }

    func changedLineRange(from previousActiveIndex: Int?, to nextActiveIndex: Int?) -> ClosedRange<Int>? {
        switch (previousActiveIndex, nextActiveIndex) {
        case let (previousActiveIndex?, nextActiveIndex?):
            min(previousActiveIndex, nextActiveIndex) ... max(previousActiveIndex, nextActiveIndex)
        case let (nil, nextActiveIndex?):
            0 ... nextActiveIndex
        case let (previousActiveIndex?, nil):
            0 ... previousActiveIndex
        case (nil, nil):
            nil
        }
    }

    func stateForLine(at index: Int, activeIndex: Int?) -> LyricTimelineCell.LineState {
        guard let activeIndex else { return .upcoming }
        if index < activeIndex { return .played }
        if index == activeIndex { return .active }
        return .upcoming
    }

    // MARK: - Initial reveal helpers

    func setVisibleCellsAlpha(_ alpha: CGFloat) {
        for cell in tableView.visibleCells {
            cell.alpha = alpha
        }
    }

    func animateInitialRevealCellVisibility(fadingOutMessage: Bool) {
        let visibleCells = tableView.visibleCells

        guard !visibleCells.isEmpty else {
            messageLabel.alpha = 1
            messageLabel.isHidden = true
            return
        }

        if fadingOutMessage {
            Interface.animate(
                duration: LyricTimelineAnimation.initialRevealDuration,
                options: LyricTimelineAnimation.easeOutOptions,
            ) {
                self.messageLabel.alpha = 0
            } completion: { _ in
                guard case .synced = self.mode else { return }
                self.messageLabel.alpha = 1
                self.messageLabel.isHidden = true
            }
        } else {
            messageLabel.alpha = 1
            messageLabel.isHidden = true
        }

        let sortedCells = visibleCells.sorted { $0.frame.minY < $1.frame.minY }
        for (index, cell) in sortedCells.enumerated() {
            guard !isAnimationSuspended else {
                cell.alpha = 1
                continue
            }
            cell.alpha = 0
            Interface.animate(
                duration: LyricTimelineAnimation.initialRevealDuration,
                delay: Double(index) * LyricTimelineAnimation.initialRevealStagger,
                options: LyricTimelineAnimation.easeOutOptions,
            ) {
                cell.alpha = 1
            }
        }
    }

    // MARK: - Scroll animation

    func animateScroll(to targetOffsetY: CGFloat) {
        guard !isAnimationSuspended else {
            setScrollOffset(to: targetOffsetY)
            return
        }

        let clampedOffsetY = clampedOffsetY(targetOffsetY)

        Interface.smoothSpringAnimate {
            self.tableView.setContentOffset(CGPoint(x: 0, y: clampedOffsetY), animated: false)
            self.layoutIfNeeded()
        }
    }

    func setScrollOffset(to targetOffsetY: CGFloat) {
        let clampedOffsetY = clampedOffsetY(targetOffsetY)
        tableView.setContentOffset(CGPoint(x: 0, y: clampedOffsetY), animated: false)
    }

    func clampedOffsetY(_ offsetY: CGFloat) -> CGFloat {
        let minimumOffsetY = -tableView.contentInset.top
        let maximumOffsetY = max(
            tableView.contentSize.height + tableView.contentInset.bottom - tableView.bounds.height,
            minimumOffsetY,
        )
        return min(max(offsetY, minimumOffsetY), maximumOffsetY)
    }
}
