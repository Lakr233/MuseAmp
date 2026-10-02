import UIKit

extension NowPlayingQueueSectionView {
    func shouldHighlight(itemIdentifier: String?) -> Bool {
        guard let itemIdentifier else {
            return false
        }
        return !ItemIdentifier.isControls(itemIdentifier)
            && !ItemIdentifier.isEmptyQueue(itemIdentifier)
            && !ItemIdentifier.isFooter(itemIdentifier)
    }

    func heightForItemIdentifier(_ itemIdentifier: String?) -> CGFloat {
        guard let itemIdentifier else {
            return queueTableView.rowHeight
        }
        if ItemIdentifier.isControls(itemIdentifier) {
            return Layout.sectionHeaderHeight
        }
        if ItemIdentifier.isEmptyQueue(itemIdentifier) {
            return 72
        }
        if ItemIdentifier.isFooter(itemIdentifier) {
            return Layout.footerRowHeight
        }
        return queueTableView.rowHeight
    }

    func tableView(_: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        shouldHighlight(itemIdentifier: itemIdentifier(for: indexPath))
    }

    func tableView(_: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        heightForItemIdentifier(itemIdentifier(for: indexPath))
    }

    func tableView(_: UITableView, heightForHeaderInSection _: Int) -> CGFloat {
        .leastNonzeroMagnitude
    }

    func tableView(_: UITableView, viewForHeaderInSection _: Int) -> UIView? {
        nil
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        guard let item = displayItem(at: indexPath) else {
            return
        }
        onSelectQueueItem(item)
    }

    func tableView(
        _: UITableView,
        contextMenuConfigurationForRowAt indexPath: IndexPath,
        point _: CGPoint,
    ) -> UIContextMenuConfiguration? {
        guard let item = displayItem(at: indexPath),
              let currentPlayerIndex = playerIndex
        else {
            return nil
        }

        let queueIndex = item.queueIndex
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
                actions.append(UIAction(
                    title: String(localized: "Remove from Queue"),
                    image: UIImage(systemName: "text.badge.minus"),
                    attributes: .destructive,
                ) { _ in
                    self?.pendingContextMenuRemoval = queueIndex
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
                    self?.onPlayNext(queueIndex)
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
        guard let queueIndex = pendingContextMenuRemoval else {
            return
        }
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
