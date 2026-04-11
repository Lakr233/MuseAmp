//
//  NowPlayingListSectionView+DataSource.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import UIKit

// MARK: - Data source

extension NowPlayingListSectionView {
    func makeDataSource() -> UITableViewDiffableDataSource<NowPlayingQueueSection, String> {
        UITableViewDiffableDataSource<NowPlayingQueueSection, String>(
            tableView: queueTableView,
        ) { [weak self] (
            tableView: UITableView,
            indexPath: IndexPath,
            item: String,
        ) -> UITableViewCell? in
            if NowPlayingQueueItemIdentifier.isControls(item) {
                guard let self,
                      let cell = tableView.dequeueReusableCell(
                          withIdentifier: NowPlayingQueueHeaderCell.reuseID,
                          for: indexPath,
                      ) as? NowPlayingQueueHeaderCell
                else {
                    return UITableViewCell()
                }

                configureQueueControlsCell(cell)
                return cell
            }

            if NowPlayingQueueItemIdentifier.isEmptyQueue(item) {
                let cell = tableView.dequeueReusableCell(
                    withIdentifier: NowPlayingQueueEmptyCell.reuseID,
                    for: indexPath,
                )
                cell.selectionStyle = .none
                return cell
            }

            if NowPlayingQueueItemIdentifier.isFooter(item) {
                guard let self,
                      let cell = tableView.dequeueReusableCell(
                          withIdentifier: NowPlayingQueueFooterCell.reuseID,
                          for: indexPath,
                      ) as? NowPlayingQueueFooterCell
                else {
                    return UITableViewCell()
                }
                configureQueueFooterCell(cell)
                return cell
            }

            guard let self,
                  let displayTrack = displayTrack(at: indexPath),
                  let cell = tableView.dequeueReusableCell(
                      withIdentifier: AmSongCell.reuseID,
                      for: indexPath,
                  ) as? AmSongCell
            else {
                return UITableViewCell()
            }

            configureQueueCell(
                cell,
                with: displayTrack.track,
                queueIndex: displayTrack.queueIndex,
            )
            return cell
        }
    }

    func applyQueueSnapshot(
        reconfiguredItems: [String],
    ) {
        AppLog.info(
            self,
            "queue snapshot start history=\(historyTracks.count) upcoming=\(queueTracks.count) reconfigured=\(reconfiguredItems.count)",
        )
        var snapshot = NSDiffableDataSourceSnapshot<NowPlayingQueueSection, String>()
        snapshot.appendSections(NowPlayingQueueSection.all)

        snapshot.appendItems(historyTracks.map(\.identifier), toSection: .history)
        snapshot.appendItems([NowPlayingQueueItemIdentifier.controls], toSection: .controls)
        let queueItems = queueTracks.isEmpty
            ? [NowPlayingQueueItemIdentifier.emptyQueue]
            : queueTracks.map(\.identifier)
        snapshot.appendItems(queueItems, toSection: .queue)
        if shouldShowFooter {
            snapshot.appendItems([NowPlayingQueueItemIdentifier.footer], toSection: .footer)
        }

        if !reconfiguredItems.isEmpty,
           hasAppliedInitialSnapshot
        {
            snapshot.reconfigureItems(reconfiguredItems)
        }

        let finishApply: () -> Void = { [weak self] in
            guard let self else {
                return
            }

            hasAppliedInitialSnapshot = true
            refreshVisibleCells()
            refreshQueueControlsCell()
            performPendingAutoScrollIfNeeded(animated: true)
            AppLog.info(
                self,
                "queue snapshot finished visibleRows=\(queueTableView.indexPathsForVisibleRows?.count ?? 0)",
            )
        }

        dataSource.apply(snapshot, animatingDifferences: false, completion: finishApply)
    }

    func makeDisplayTracks(
        queue: [PlaybackTrack],
        playerIndex: Int?,
    ) -> (history: [NowPlayingQueueDisplayTrack], queue: [NowPlayingQueueDisplayTrack]) {
        var occurrences: [String: Int] = [:]
        var allHistory: [NowPlayingQueueDisplayTrack] = []
        var allQueue: [NowPlayingQueueDisplayTrack] = []

        allHistory.reserveCapacity(playerIndex ?? 0)
        allQueue.reserveCapacity(queue.count)

        for (queueIndex, track) in queue.enumerated() {
            let occurrence = occurrences[track.id, default: 0]
            occurrences[track.id] = occurrence + 1

            let isHistoryTrack = playerIndex.map { queueIndex < $0 } ?? false
            let identifier = NowPlayingQueueItemIdentifier.track(
                trackID: track.id,
                occurrence: occurrence,
            )
            let displayTrack = NowPlayingQueueDisplayTrack(
                identifier: identifier,
                queueIndex: queueIndex,
                track: track,
            )

            if isHistoryTrack {
                allHistory.append(displayTrack)
            } else {
                allQueue.append(displayTrack)
            }
        }

        let trimmedHistory = allHistory.suffix(Layout.maxVisibleHistoryTracks)
        let trimmedQueue = allQueue.prefix(Layout.maxVisibleQueueTracks)
        return (Array(trimmedHistory), Array(trimmedQueue))
    }

    func reconfiguredItemIdentifiers(
        didTrackContentChange: Bool,
        previousPlayerIndex: Int?,
        currentPlayerIndex: Int?,
    ) -> [String] {
        if didTrackContentChange {
            return historyTracks.map(\.identifier) + queueTracks.map(\.identifier)
        }

        let impactedIndexes = [previousPlayerIndex, currentPlayerIndex].compactMap(\.self)
        guard !impactedIndexes.isEmpty else {
            return []
        }

        var impactedIdentifiers: [String] = []
        impactedIdentifiers.reserveCapacity(impactedIndexes.count)

        for queueIndex in impactedIndexes {
            if let item = historyTracks.first(where: { $0.queueIndex == queueIndex })?.identifier,
               !impactedIdentifiers.contains(item)
            {
                impactedIdentifiers.append(item)
            }

            if let item = queueTracks.first(where: { $0.queueIndex == queueIndex })?.identifier,
               !impactedIdentifiers.contains(item)
            {
                impactedIdentifiers.append(item)
            }
        }

        return impactedIdentifiers
    }

    func displayTrack(at indexPath: IndexPath) -> NowPlayingQueueDisplayTrack? {
        guard let section = NowPlayingQueueSection(rawValue: indexPath.section) else {
            return nil
        }

        switch section {
        case .history:
            guard historyTracks.indices.contains(indexPath.row) else {
                return nil
            }
            return historyTracks[indexPath.row]
        case .controls, .footer:
            return nil
        case .queue:
            guard queueTracks.indices.contains(indexPath.row) else {
                return nil
            }
            return queueTracks[indexPath.row]
        }
    }

    func configureQueueCell(
        _ cell: AmSongCell,
        with track: PlaybackTrack,
        queueIndex: Int,
    ) {
        let isCurrentTrack = queueIndex == playerIndex
        let isPlayedTrack = playerIndex.map { queueIndex < $0 } ?? false
        cell.applyAppearanceStyle(.nowPlaying)
        cell.configure(
            with: track,
            trailingText: isCurrentTrack ? "▶︎ \(queueIndex + 1)" : "\(queueIndex + 1)",
        )
        cell.setRowInsets(Layout.queueRowInsets)
        cell.setTrailingLabelHidden(false)
        cell.backgroundColor = .clear
        cell.contentView.backgroundColor = isCurrentTrack
            ? UIColor.white.withAlphaComponent(0.08)
            : .clear
        cell.contentView.alpha = isPlayedTrack ? 0.58 : 1
        cell.selectionStyle = .none
        cell.separatorInset = .zero
        cell.layoutMargins = .zero
    }

    func refreshVisibleCells() {
        for indexPath in queueTableView.indexPathsForVisibleRows ?? [] {
            guard let cell = queueTableView.cellForRow(at: indexPath) as? AmSongCell,
                  let displayTrack = displayTrack(at: indexPath)
            else {
                continue
            }

            configureQueueCell(
                cell,
                with: displayTrack.track,
                queueIndex: displayTrack.queueIndex,
            )
        }
    }

    func refreshQueueControlsCell() {
        let indexPath = IndexPath(row: 0, section: NowPlayingQueueSection.controls.rawValue)
        guard let cell = queueTableView.cellForRow(at: indexPath) as? NowPlayingQueueHeaderCell else {
            return
        }

        configureQueueControlsCell(cell)
    }

    func configureQueueControlsCell(_ cell: NowPlayingQueueHeaderCell) {
        cell.configure(
            title: String(localized: "Player Queue"),
            repeatMode: repeatMode,
            isShuffleFeedbackActive: isShuffleFeedbackActive,
            onShuffleTap: { [weak self] in self?.onToggleShuffle() },
            onRepeatTap: { [weak self] in self?.onCycleRepeatMode() },
        )
    }

    var shouldShowFooter: Bool {
        guard let idx = fullQueuePlayerIndex else { return false }
        let totalUpcoming = fullQueueTracks.count - idx
        return totalUpcoming > Layout.maxVisibleQueueTracks
    }

    var footerRemainingCount: Int {
        guard let idx = fullQueuePlayerIndex else { return 0 }
        let totalUpcoming = fullQueueTracks.count - idx
        return max(totalUpcoming - Layout.maxVisibleQueueTracks, 0)
    }

    var footerTotalMinutes: Int {
        guard let idx = fullQueuePlayerIndex else { return 0 }
        let upcomingTracks = fullQueueTracks[idx...]
        let totalSeconds = upcomingTracks.reduce(0.0) { $0 + ($1.durationInSeconds ?? 0) }
        return Int((totalSeconds / 60).rounded())
    }

    func configureQueueFooterCell(_ cell: NowPlayingQueueFooterCell) {
        cell.configure(
            remainingCount: footerRemainingCount,
            totalMinutes: footerTotalMinutes,
        )
    }

    func updateSpacerFramesIfNeeded() {
        let targetWidth = max(queueTableView.bounds.width, 1)
        let headerHeight = Layout.headerSpacerHeight
        let footerHeight = Layout.footerSpacerHeight

        let headerFrame = CGRect(x: 0, y: 0, width: targetWidth, height: headerHeight)
        let footerFrame = CGRect(x: 0, y: 0, width: targetWidth, height: footerHeight)

        var didUpdate = false
        if headerSpacerView.frame != headerFrame {
            headerSpacerView.frame = headerFrame
            queueTableView.tableHeaderView = headerSpacerView
            didUpdate = true
        }
        if footerSpacerView.frame != footerFrame {
            footerSpacerView.frame = footerFrame
            queueTableView.tableFooterView = footerSpacerView
            didUpdate = true
        }

        if didUpdate {
            AppLog.verbose(
                self,
                "queue spacers updated header=\(String(format: "%.2f", headerHeight)) footer=\(String(format: "%.2f", footerHeight)) width=\(String(format: "%.2f", targetWidth))",
            )
        }
    }
}
