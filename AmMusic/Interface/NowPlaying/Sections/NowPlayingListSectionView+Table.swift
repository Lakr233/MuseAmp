//
//  NowPlayingListSectionView+Table.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import UIKit

// MARK: - UITableViewDelegate

extension NowPlayingListSectionView: UITableViewDelegate {
    func tableView(_: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return false }
        return !NowPlayingQueueItemIdentifier.isControls(item)
            && !NowPlayingQueueItemIdentifier.isEmptyQueue(item)
            && !NowPlayingQueueItemIdentifier.isFooter(item)
    }

    func tableView(_: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        guard let item = dataSource.itemIdentifier(for: indexPath) else {
            return queueTableView.rowHeight
        }

        if NowPlayingQueueItemIdentifier.isControls(item) {
            return Layout.sectionHeaderHeight
        }

        if NowPlayingQueueItemIdentifier.isEmptyQueue(item) {
            return 72
        }

        if NowPlayingQueueItemIdentifier.isFooter(item) {
            return Layout.footerRowHeight
        }

        return queueTableView.rowHeight
    }

    func tableView(_: UITableView, heightForHeaderInSection _: Int) -> CGFloat {
        .leastNonzeroMagnitude
    }

    func tableView(_: UITableView, viewForHeaderInSection _: Int) -> UIView? {
        nil
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        guard let displayTrack = displayTrack(at: indexPath) else { return }
        onSelectQueueTrack(.queue(index: displayTrack.queueIndex))
    }

    func tableView(
        _: UITableView,
        contextMenuConfigurationForRowAt indexPath: IndexPath,
        point _: CGPoint,
    ) -> UIContextMenuConfiguration? {
        guard let displayTrack = displayTrack(at: indexPath),
              let currentPlayerIndex = playerIndex
        else {
            return nil
        }

        let queueIndex = displayTrack.queueIndex
        let track = displayTrack.track
        let isCurrentTrack = queueIndex == currentPlayerIndex
        let isHistoryTrack = queueIndex < currentPlayerIndex

        return UIContextMenuConfiguration(
            identifier: indexPath as NSIndexPath,
            previewProvider: nil,
        ) { [weak self] _ in
            var actions: [UIAction] = []

            if isCurrentTrack {
                actions.append(UIAction(
                    title: String(localized: "Play from Beginning"),
                    image: UIImage(systemName: "arrow.counterclockwise"),
                ) { _ in
                    self?.onRestartCurrentTrack()
                })
            } else if isHistoryTrack {
                actions.append(UIAction(
                    title: String(localized: "Play from Here"),
                    image: UIImage(systemName: "play"),
                ) { _ in
                    self?.onPlayFromHere(queueIndex)
                })
                actions.append(UIAction(
                    title: String(localized: "Play Next"),
                    image: UIImage(systemName: "text.line.first.and.arrowtriangle.forward"),
                ) { _ in
                    self?.onPlayNext(track)
                })
            } else {
                actions.append(UIAction(
                    title: String(localized: "Play from Here"),
                    image: UIImage(systemName: "play"),
                ) { _ in
                    self?.onPlayFromHere(queueIndex)
                })
                actions.append(UIAction(
                    title: String(localized: "Remove from Queue"),
                    image: UIImage(systemName: "text.badge.minus"),
                    attributes: .destructive,
                ) { _ in
                    self?.pendingContextMenuRemoval = queueIndex
                })
            }

            return UIMenu(children: actions)
        }
    }

    func tableView(
        _: UITableView,
        previewForHighlightingContextMenuWithConfiguration configuration: UIContextMenuConfiguration,
    ) -> UITargetedPreview? {
        CellContextMenuPreviewHelper.targetedPreview(
            for: configuration,
            in: queueTableView,
            backgroundColor: UIColor.white.withAlphaComponent(0.08),
        )
    }

    func tableView(
        _: UITableView,
        previewForDismissingContextMenuWithConfiguration configuration: UIContextMenuConfiguration,
    ) -> UITargetedPreview? {
        CellContextMenuPreviewHelper.targetedPreview(
            for: configuration,
            in: queueTableView,
            backgroundColor: UIColor.white.withAlphaComponent(0.08),
        )
    }

    func tableView(
        _: UITableView,
        willEndContextMenuInteraction _: UIContextMenuConfiguration,
        animator: (any UIContextMenuInteractionAnimating)?,
    ) {
        guard let queueIndex = pendingContextMenuRemoval else { return }
        pendingContextMenuRemoval = nil

        if let animator {
            animator.addCompletion { [weak self] in
                self?.onRemoveQueueTrack(queueIndex)
            }
        } else {
            onRemoveQueueTrack(queueIndex)
        }
    }
}

// MARK: - Auto-scroll

extension NowPlayingListSectionView {
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

        AppLog.info(
            self,
            "queue refresh autoscroll targetOffsetY=\(String(format: "%.2f", targetOffsetY)) anchor=\(queueTracks.isEmpty ? "controls-top" : "current-row@1/3") animated=\(animated) viewportHeight=\(String(format: "%.2f", queueTableView.bounds.height))",
        )

        if animated {
            animateScroll(to: targetOffsetY)
        } else {
            setScrollOffset(to: targetOffsetY)
        }
    }

    func targetQueueAnchorOffsetY() -> CGFloat {
        let adjustedTopInset = queueTableView.adjustedContentInset.top
        let historyHeight = CGFloat(historyTracks.count) * Layout.queueRowHeight
        let controlsTopY = Layout.headerSpacerHeight + historyHeight

        if queueTracks.isEmpty {
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
