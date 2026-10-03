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
        tableView.applySoftEdgeEffects()
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
}
