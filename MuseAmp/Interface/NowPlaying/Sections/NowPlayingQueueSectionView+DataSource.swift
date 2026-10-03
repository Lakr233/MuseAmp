import UIKit

extension NowPlayingQueueSectionView {
    func displayItem(at indexPath: IndexPath) -> AMQueueItemContent? {
        guard let section = QueueSection(rawValue: indexPath.section) else {
            return nil
        }

        switch section {
        case .history:
            guard queueSnapshot.historyItems.indices.contains(indexPath.row) else {
                return nil
            }
            return queueSnapshot.historyItems[indexPath.row]
        case .controls, .footer:
            return nil
        case .queue:
            guard queueSnapshot.upcomingItems.indices.contains(indexPath.row) else {
                return nil
            }
            return queueSnapshot.upcomingItems[indexPath.row]
        }
    }

    func configureQueueCell(
        _ cell: AmSongCell,
        with item: AMQueueItemContent,
    ) {
        cell.configure(content: SongRowContent(
            title: item.title,
            subtitle: item.subtitle,
            trailingText: item.positionText,
            artworkURL: item.artworkURL,
            appearanceStyle: .nowPlaying,
        ))
        cell.setRowInsets(Layout.queueRowInsets)
        cell.setTrailingLabelHidden(false)
        cell.backgroundColor = .clear
        cell.contentView.backgroundColor = item.isCurrent
            ? UIColor.white.withAlphaComponent(0.08)
            : .clear
        cell.contentView.layer.cornerRadius = traitCollection.horizontalSizeClass == .regular ? 8 : 0
        cell.contentView.alpha = item.isPlayed ? 0.58 : 1
        cell.selectionStyle = .none
        cell.separatorInset = .zero
        cell.layoutMargins = .zero
    }

    func refreshVisibleCells() {
        for indexPath in queueTableView.indexPathsForVisibleRows ?? [] {
            guard let cell = queueTableView.cellForRow(at: indexPath) as? AmSongCell,
                  let item = displayItem(at: indexPath)
            else {
                continue
            }

            configureQueueCell(cell, with: item)
        }
    }

    func refreshQueueControlsCell() {
        let indexPath = IndexPath(row: 0, section: QueueSection.controls.rawValue)
        guard let cell = queueTableView.cellForRow(at: indexPath) as? NowPlayingQueueHeaderCell else {
            return
        }

        configureQueueControlsCell(cell)
    }

    func configureQueueControlsCell(_ cell: NowPlayingQueueHeaderCell) {
        cell.configure(
            content: queueSnapshot.headerContent,
            onShuffleTap: { [weak self] in self?.onToggleShuffle() },
            onRepeatTap: { [weak self] in self?.onCycleRepeatMode() },
        )
    }

    func refreshQueueFooterCell() {
        let indexPath = IndexPath(row: 0, section: QueueSection.footer.rawValue)
        guard let cell = queueTableView.cellForRow(at: indexPath) as? NowPlayingQueueFooterCell else {
            return
        }
        configureQueueFooterCell(cell)
    }

    func configureQueueFooterCell(_ cell: NowPlayingQueueFooterCell) {
        guard let footerContent = queueSnapshot.footerContent else {
            return
        }
        cell.configure(content: footerContent)
    }

    // MARK: - UITableViewDataSource

    func itemIdentifier(for indexPath: IndexPath) -> String? {
        guard let section = QueueSection(rawValue: indexPath.section) else {
            return nil
        }
        switch section {
        case .history:
            guard queueSnapshot.historyItems.indices.contains(indexPath.row) else { return nil }
            return queueSnapshot.historyItems[indexPath.row].id
        case .controls:
            return indexPath.row == 0 ? ItemIdentifier.controls : nil
        case .queue:
            if queueSnapshot.upcomingItems.isEmpty {
                return indexPath.row == 0 ? ItemIdentifier.emptyQueue : nil
            }
            guard queueSnapshot.upcomingItems.indices.contains(indexPath.row) else { return nil }
            return queueSnapshot.upcomingItems[indexPath.row].id
        case .footer:
            return indexPath.row == 0 ? ItemIdentifier.footer : nil
        }
    }

    func numberOfSections(in _: UITableView) -> Int {
        QueueSection.all.count
    }

    func tableView(_: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let queueSection = QueueSection(rawValue: section) else {
            return 0
        }
        switch queueSection {
        case .history:
            return queueSnapshot.historyItems.count
        case .controls:
            return 1
        case .queue:
            return queueSnapshot.upcomingItems.isEmpty ? 1 : queueSnapshot.upcomingItems.count
        case .footer:
            return queueSnapshot.footerContent != nil ? 1 : 0
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let section = QueueSection(rawValue: indexPath.section) else {
            return UITableViewCell()
        }

        switch section {
        case .controls:
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: NowPlayingQueueHeaderCell.reuseID,
                for: indexPath,
            ) as? NowPlayingQueueHeaderCell else {
                return UITableViewCell()
            }
            configureQueueControlsCell(cell)
            return cell

        case .queue where queueSnapshot.upcomingItems.isEmpty:
            let cell = tableView.dequeueReusableCell(
                withIdentifier: NowPlayingQueueEmptyCell.reuseID,
                for: indexPath,
            )
            cell.selectionStyle = .none
            return cell

        case .footer:
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: NowPlayingQueueFooterCell.reuseID,
                for: indexPath,
            ) as? NowPlayingQueueFooterCell else {
                return UITableViewCell()
            }
            configureQueueFooterCell(cell)
            return cell

        case .history, .queue:
            guard let item = displayItem(at: indexPath),
                  let cell = tableView.dequeueReusableCell(
                      withIdentifier: AmSongCell.reuseID,
                      for: indexPath,
                  ) as? AmSongCell
            else {
                return UITableViewCell()
            }
            configureQueueCell(cell, with: item)
            return cell
        }
    }
}
