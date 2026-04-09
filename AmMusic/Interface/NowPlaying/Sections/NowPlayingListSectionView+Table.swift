import UIKit

// MARK: - UITableViewDelegate

extension NowPlayingListSectionView: UITableViewDelegate {
    func tableView(_: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return false }
        return !NowPlayingQueueItemIdentifier.isControls(item)
            && !NowPlayingQueueItemIdentifier.isEmptyQueue(item)
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
        onSelectQueueTrack?(.queue(index: displayTrack.queueIndex))
    }

    func tableView(
        _: UITableView,
        contextMenuConfigurationForRowAt indexPath: IndexPath,
        point _: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard let displayTrack = displayTrack(at: indexPath),
              let currentPlayerIndex = playerIndex,
              displayTrack.queueIndex > currentPlayerIndex
        else {
            return nil
        }

        let queueIndex = displayTrack.queueIndex
        return UIContextMenuConfiguration(
            identifier: indexPath as NSIndexPath,
            previewProvider: nil
        ) { [weak self] _ in
            let removeAction = UIAction(
                title: String(localized: "Remove from Queue"),
                image: UIImage(systemName: "text.badge.minus"),
                attributes: .destructive
            ) { _ in
                self?.pendingContextMenuRemoval = queueIndex
            }
            return UIMenu(children: [removeAction])
        }
    }

    func tableView(
        _: UITableView,
        previewForHighlightingContextMenuWithConfiguration configuration: UIContextMenuConfiguration
    ) -> UITargetedPreview? {
        CellContextMenuPreviewHelper.targetedPreview(
            for: configuration,
            in: queueTableView,
            backgroundColor: UIColor.white.withAlphaComponent(0.08)
        )
    }

    func tableView(
        _: UITableView,
        previewForDismissingContextMenuWithConfiguration configuration: UIContextMenuConfiguration
    ) -> UITargetedPreview? {
        CellContextMenuPreviewHelper.targetedPreview(
            for: configuration,
            in: queueTableView,
            backgroundColor: UIColor.white.withAlphaComponent(0.08)
        )
    }

    func tableView(
        _: UITableView,
        willEndContextMenuInteraction _: UIContextMenuConfiguration,
        animator: (any UIContextMenuInteractionAnimating)?
    ) {
        guard let queueIndex = pendingContextMenuRemoval else { return }
        pendingContextMenuRemoval = nil

        if let animator {
            animator.addCompletion { [weak self] in
                self?.onRemoveQueueTrack?(queueIndex)
            }
        } else {
            onRemoveQueueTrack?(queueIndex)
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
            "queue refresh autoscroll targetOffsetY=\(String(format: "%.2f", targetOffsetY)) anchor=\(queueTracks.isEmpty ? "controls-top" : "current-row@1/3") animated=\(animated) viewportHeight=\(String(format: "%.2f", queueTableView.bounds.height))"
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

        InterfaceAnimation.smoothSpringAnimate {
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

            guard let blockedUntil = isProgramaticScrollBlocked,
                  blockedUntil <= Date()
            else {
                return
            }

            isProgramaticScrollBlocked = nil
            performPendingAutoScrollIfNeeded(animated: true)
        }

        pendingProgrammaticScrollRetry = retryWorkItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Layout.programmaticScrollBlockDuration,
            execute: retryWorkItem
        )
    }

    func hasActiveProgrammaticScrollBlock() -> Bool {
        guard let blockedUntil = isProgramaticScrollBlocked else {
            return false
        }

        if blockedUntil <= Date() {
            isProgramaticScrollBlocked = nil
            return false
        }

        return true
    }

    func clampedOffsetY(_ offsetY: CGFloat) -> CGFloat {
        let maximumOffsetY = max(
            queueTableView.contentSize.height
                + queueTableView.adjustedContentInset.bottom
                - queueTableView.bounds.height,
            -queueTableView.adjustedContentInset.top
        )
        return min(max(offsetY, -queueTableView.adjustedContentInset.top), maximumOffsetY)
    }
}
