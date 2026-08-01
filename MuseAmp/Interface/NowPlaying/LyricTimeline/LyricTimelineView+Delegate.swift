import Combine
import UIKit

extension LyricTimelineView: UITableViewDataSource, UITableViewDelegate {
    // MARK: - DataSource

    func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
        items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let item = items[indexPath.row]
        switch item {
        case let .spacer(height):
            let cell = tableView.dequeueReusableCell(
                withIdentifier: String(describing: LyricTimelineSpacerCell.self),
                for: indexPath,
            ) as! LyricTimelineSpacerCell
            cell.configure(height: height)
            return cell
        case let .message(text):
            let cell = tableView.dequeueReusableCell(
                withIdentifier: String(describing: LyricTimelineMessageCell.self),
                for: indexPath,
            ) as! LyricTimelineMessageCell
            cell.configure(text: text)
            return cell
        case let .line(_, text, isActive):
            let cell = tableView.dequeueReusableCell(
                withIdentifier: String(describing: LyricTimelineCell.self),
                for: indexPath,
            ) as! LyricTimelineCell
            cell.configure(text: text, horizontalInset: Layout.minimumHorizontalInset, isActive: isActive)
            return cell
        case let .staticLine(_, text):
            let cell = tableView.dequeueReusableCell(
                withIdentifier: String(describing: StaticLyricCell.self),
                for: indexPath,
            ) as! StaticLyricCell
            cell.configure(text: text, horizontalInset: Layout.minimumHorizontalInset, isActive: true)
            return cell
        }
    }

    // MARK: - Row Height

    func tableView(_: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        let item = items[indexPath.row]
        if case .message = item {
            let spacerTotal = items.reduce(CGFloat(0)) { sum, item in
                if case let .spacer(h) = item {
                    return sum + h
                }
                return sum
            }
            return max(44, tableView.bounds.height - spacerTotal)
        }
        return UITableView.automaticDimension
    }

    // MARK: - Selection

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        guard case .line = items[indexPath.row] else {
            AppLog.verbose(self, "didSelectRow ignored non-line row=\(indexPath.row)")
            return
        }
        AppLog.info(self, "didSelectRow seeking row=\(indexPath.row)")
        seekToLine(at: indexPath.row)
        interactionSubject.send()
        scrollToRow(indexPath.row)
    }

    // MARK: - Context Menu

    func tableView(
        _: UITableView,
        contextMenuConfigurationForRowAt indexPath: IndexPath,
        point _: CGPoint,
    ) -> UIContextMenuConfiguration? {
        switch items[indexPath.row] {
        case .line, .staticLine: break
        case .spacer, .message: return nil
        }
        interactionSubject.send()
        return UIContextMenuConfiguration(identifier: indexPath as NSIndexPath, previewProvider: nil) { [weak self] _ in
            self?.makeLineContextMenu(at: indexPath.row)
        }
    }

    func tableView(
        _: UITableView,
        previewForHighlightingContextMenuWithConfiguration configuration: UIContextMenuConfiguration,
    ) -> UITargetedPreview? {
        CellContextMenuPreviewHelper.targetedPreview(
            for: configuration,
            in: tableView,
            backgroundColor: .clear,
        )
    }

    func tableView(
        _: UITableView,
        previewForDismissingContextMenuWithConfiguration configuration: UIContextMenuConfiguration,
    ) -> UITargetedPreview? {
        CellContextMenuPreviewHelper.targetedPreview(
            for: configuration,
            in: tableView,
            backgroundColor: .clear,
        )
    }

    // MARK: - Scroll Delegate

    func scrollViewWillBeginDragging(_: UIScrollView) {
        interactionSubject.send()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating else { return }
        interactionSubject.send()
    }

    func scrollViewDidEndDragging(_: UIScrollView, willDecelerate _: Bool) {}

    func scrollViewDidEndDecelerating(_: UIScrollView) {}

    // MARK: - Programmatic Scroll

    func focusCurrentLine(isUserInitialed: Bool) {
        if isProgrammaticScrollSuppressed, !isUserInitialed {
            AppLog.verbose(self, "focusCurrentLine skipped, programmatic scroll suppressed")
            return
        }

        guard let activeRow = items.firstIndex(where: {
            if case let .line(_, _, isActive) = $0 {
                return isActive
            }
            return false
        }) else {
            // Timed lyrics with no active line means playback sits before the
            // first timestamp (e.g. right after a track change). Reset to the
            // top instead of staying wherever the previous song left the list.
            let hasTimedLines = items.contains {
                if case .line = $0 {
                    return true
                }
                return false
            }
            if hasTimedLines {
                AppLog.verbose(self, "focusCurrentLine no active line, resetting to top")
                scrollToTop()
            } else {
                AppLog.verbose(self, "focusCurrentLine no active line")
            }
            return
        }

        AppLog.verbose(self, "focusCurrentLine activeRow=\(activeRow) userInitiated=\(isUserInitialed)")
        scrollToRow(activeRow)
    }

    func scrollToTop() {
        guard tableView.contentOffset.y > 5 else {
            return
        }
        Interface.smoothSpringAnimate {
            self.tableView.setContentOffset(.zero, animated: false)
            self.layoutIfNeeded()
        }
    }

    func scrollToRow(_ row: Int) {
        layoutIfNeeded()

        let indexPath = IndexPath(row: row, section: 0)
        let cellRect = tableView.rectForRow(at: indexPath)
        let targetY = cellRect.midY - tableView.bounds.height * Layout.activeLineAnchorFraction
        let maxY = tableView.contentSize.height - tableView.bounds.height
        let clampedY = min(max(targetY, 0), max(maxY, 0))

        guard abs(tableView.contentOffset.y - clampedY) > 5 else {
            AppLog.verbose(self, "scrollToRow row=\(row) skipped, already in position")
            return
        }
        AppLog.verbose(self, "scrollToRow row=\(row) target=\(Int(clampedY)) current=\(Int(tableView.contentOffset.y))")
        Interface.smoothSpringAnimate {
            self.tableView.setContentOffset(CGPoint(x: 0, y: clampedY), animated: false)
            self.layoutIfNeeded()
        }
    }
}
