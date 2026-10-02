import SnapKit
import UIKit

struct NowPlayingQueuePresentationUpdate: Equatable {
    let didHistoryIdentityChange: Bool
    let didQueueIdentityChange: Bool
    let didFooterVisibilityChange: Bool
    let didTrackContentChange: Bool
    let didPlayerIndexChange: Bool
    let didHeaderContentChange: Bool
    let didFooterContentChange: Bool

    var didIdentityChange: Bool {
        didHistoryIdentityChange || didQueueIdentityChange || didFooterVisibilityChange
    }

    var appliedSnapshot: Bool {
        didIdentityChange || didTrackContentChange || didPlayerIndexChange
    }
}

@MainActor
class NowPlayingQueueSectionView: UIView, UITableViewDataSource, UITableViewDelegate {
    nonisolated enum Layout {
        static let verticalInset: CGFloat = 12
        static let horizontalInset: CGFloat = 20
        static let headerSpacerHeight: CGFloat = 100
        static let sectionHeaderHeight: CGFloat = 56
        static let queueRowHeight: CGFloat = 56
        static let activeRowAnchorFraction: CGFloat = 1.0 / 3.0
        static let footerSpacerHeight: CGFloat = 100
        static let programmaticScrollBlockDuration: TimeInterval = 1.0
        static let maxVisibleHistoryTracks = 3
        static let maxVisibleQueueTracks = 10
        static let footerRowHeight: CGFloat = 44
        static let queueRowInsets = UIEdgeInsets(
            top: 6,
            left: horizontalInset,
            bottom: 6,
            right: horizontalInset,
        )
    }

    nonisolated enum QueueSection: Int, Hashable {
        case history
        case controls
        case queue
        case footer

        static let all: [QueueSection] = [.history, .controls, .queue, .footer]
    }

    nonisolated enum ItemIdentifier {
        static let controls = "queueControls"
        static let emptyQueue = "emptyQueue"
        static let footer = "queueFooter"

        static func track(trackID: String, occurrence: Int) -> String {
            "track:\(occurrence):\(trackID)"
        }

        static func isEmptyQueue(_ identifier: String) -> Bool {
            identifier == emptyQueue
        }

        static func isControls(_ identifier: String) -> Bool {
            identifier == controls
        }

        static func isFooter(_ identifier: String) -> Bool {
            identifier == footer
        }
    }

    var onToggleShuffle: () -> Void = {}
    var onCycleRepeatMode: () -> Void = {}
    var onSelectQueueItem: (AMQueueItemContent) -> Void = { _ in }
    var onRemoveQueueTrack: (Int) -> Void = { _ in }
    var onRestartCurrentTrack: () -> Void = {}
    var onPlayFromHere: (Int) -> Void = { _ in }
    var onPlayNext: (Int) -> Void = { _ in }
    var pendingContextMenuRemoval: Int?

    let queueTableView: UITableView = {
        let tableView = UITableView(frame: UIScreen.main.bounds, style: .plain)
        tableView.backgroundColor = .clear
        tableView.clipsToBounds = false
        tableView.allowsSelection = true
        tableView.contentInset = UIEdgeInsets(
            top: Layout.verticalInset,
            left: 0,
            bottom: Layout.verticalInset,
            right: 0,
        )
        tableView.scrollIndicatorInsets = UIEdgeInsets(
            top: Layout.verticalInset,
            left: 0,
            bottom: Layout.verticalInset,
            right: 0,
        )
        tableView.separatorStyle = .none
        tableView.showsVerticalScrollIndicator = false
        tableView.alwaysBounceVertical = false
        tableView.contentInsetAdjustmentBehavior = .never
        tableView.insetsContentViewsToSafeArea = false
        tableView.rowHeight = Layout.queueRowHeight
        tableView.sectionFooterHeight = 0
        tableView.register(
            AmSongCell.self,
            forCellReuseIdentifier: AmSongCell.reuseID,
        )
        tableView.register(
            NowPlayingQueueHeaderCell.self,
            forCellReuseIdentifier: NowPlayingQueueHeaderCell.reuseID,
        )
        tableView.register(
            NowPlayingQueueEmptyCell.self,
            forCellReuseIdentifier: NowPlayingQueueEmptyCell.reuseID,
        )
        tableView.register(
            NowPlayingQueueFooterCell.self,
            forCellReuseIdentifier: NowPlayingQueueFooterCell.reuseID,
        )
        tableView.sectionHeaderTopPadding = 0
        return tableView
    }()

    var queueSnapshot: AMNowPlayingQueueSnapshot = .empty
    var playerIndex: Int?
    var hasAppliedInitialSnapshot = false
    var pendingAutoScrollToQueueStart = false
    var needsInitialAutoScrollOnPresent = true
    var isProgramaticScrollBlocked: Date = .distantPast
    var pendingProgrammaticScrollRetry: DispatchWorkItem?
    let headerSpacerView = UIView()
    let footerSpacerView = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        headerSpacerView.backgroundColor = .clear
        footerSpacerView.backgroundColor = .clear
        headerSpacerView.frame = CGRect(x: 0, y: 0, width: 1, height: Layout.headerSpacerHeight)
        footerSpacerView.frame = CGRect(x: 0, y: 0, width: 1, height: Layout.footerSpacerHeight)
        queueTableView.tableHeaderView = headerSpacerView
        queueTableView.tableFooterView = footerSpacerView
        queueTableView.dataSource = self
        queueTableView.delegate = self

        addSubview(queueTableView)
        queueTableView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateSpacerFramesIfNeeded()
    }

    func didApplyQueueSnapshot() {}

    func logAutoScroll(targetOffsetY _: CGFloat, animated _: Bool) {}

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

    func applyQueueSnapshot(changedSections: IndexSet) {
        guard hasAppliedInitialSnapshot else {
            queueTableView.reloadData()
            hasAppliedInitialSnapshot = true
            finishApplyingQueueSnapshot()
            return
        }

        guard !changedSections.isEmpty else {
            finishApplyingQueueSnapshot()
            return
        }

        queueTableView.performBatchUpdates {
            queueTableView.reloadSections(changedSections, with: .fade)
        } completion: { [weak self] _ in
            guard let self else {
                return
            }
            finishApplyingQueueSnapshot()
        }
    }

    private func finishApplyingQueueSnapshot() {
        refreshVisibleCells()
        refreshQueueControlsCell()
        refreshQueueFooterCell()
        didApplyQueueSnapshot()
    }

    @discardableResult
    func updateQueuePresentation(
        nextSnapshot: AMNowPlayingQueueSnapshot,
        playerIndex: Int?,
    ) -> NowPlayingQueuePresentationUpdate {
        let previousSnapshot = queueSnapshot
        let previousPlayerIndex = self.playerIndex

        let didHistoryIdentityChange = previousSnapshot.historyItems.map(\.id) != nextSnapshot.historyItems.map(\.id)
        let didQueueIdentityChange = previousSnapshot.upcomingItems.map(\.id) != nextSnapshot.upcomingItems.map(\.id)
        let didFooterVisibilityChange = (previousSnapshot.footerContent != nil) != (nextSnapshot.footerContent != nil)
        let didTrackContentChange = previousSnapshot.historyItems != nextSnapshot.historyItems
            || previousSnapshot.upcomingItems != nextSnapshot.upcomingItems
        let didPlayerIndexChange = previousPlayerIndex != playerIndex
        let didHeaderContentChange = previousSnapshot.headerContent != nextSnapshot.headerContent
        let didFooterContentChange = previousSnapshot.footerContent != nextSnapshot.footerContent

        queueSnapshot = nextSnapshot
        self.playerIndex = playerIndex

        if didPlayerIndexChange {
            pendingAutoScrollToQueueStart = true
            if hasAppliedInitialSnapshot {
                blockProgrammaticScroll()
            }
        }

        let update = NowPlayingQueuePresentationUpdate(
            didHistoryIdentityChange: didHistoryIdentityChange,
            didQueueIdentityChange: didQueueIdentityChange,
            didFooterVisibilityChange: didFooterVisibilityChange,
            didTrackContentChange: didTrackContentChange,
            didPlayerIndexChange: didPlayerIndexChange,
            didHeaderContentChange: didHeaderContentChange,
            didFooterContentChange: didFooterContentChange,
        )

        if update.appliedSnapshot {
            var changedSections = IndexSet()
            if didHistoryIdentityChange { changedSections.insert(QueueSection.history.rawValue) }
            if didQueueIdentityChange { changedSections.insert(QueueSection.queue.rawValue) }
            if didFooterVisibilityChange { changedSections.insert(QueueSection.footer.rawValue) }
            applyQueueSnapshot(changedSections: changedSections)
        } else {
            if didHeaderContentChange {
                refreshQueueControlsCell()
            }
            if didFooterContentChange {
                refreshQueueFooterCell()
            }
            performPendingAutoScrollIfNeeded(animated: false)
        }

        return update
    }

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

    func updateSpacerFramesIfNeeded() {
        let targetWidth = max(queueTableView.bounds.width, 1)
        let headerFrame = CGRect(
            x: 0,
            y: 0,
            width: targetWidth,
            height: Layout.headerSpacerHeight,
        )
        let footerFrame = CGRect(
            x: 0,
            y: 0,
            width: targetWidth,
            height: Layout.footerSpacerHeight,
        )

        if headerSpacerView.frame != headerFrame {
            headerSpacerView.frame = headerFrame
            queueTableView.tableHeaderView = headerSpacerView
        }
        if footerSpacerView.frame != footerFrame {
            footerSpacerView.frame = footerFrame
            queueTableView.tableFooterView = footerSpacerView
        }
    }

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
