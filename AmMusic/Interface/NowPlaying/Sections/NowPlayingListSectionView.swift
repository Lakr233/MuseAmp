//
//  NowPlayingListSectionView.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import AmMusicPlayerKit
import Combine
import ConfigurableKit
import SnapKit
import Then
import UIKit

nonisolated enum NowPlayingQueueSection: Int, Hashable {
    case history
    case controls
    case queue
    case footer

    static let all: [NowPlayingQueueSection] = [.history, .controls, .queue, .footer]
}

enum NowPlayingQueueItemIdentifier {
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

struct NowPlayingQueueDisplayTrack: Equatable {
    let identifier: String
    let queueIndex: Int
    let track: PlaybackTrack
}

enum NowPlayingQueueTrackSelection {
    case queue(index: Int)
}

final class NowPlayingListSectionView: UIView {
    enum Layout {
        static let verticalInset: CGFloat = 12
        static let horizontalInset: CGFloat = 20
        static let headerSpacerHeight: CGFloat = 100
        static let sectionHeaderHeight: CGFloat = 56
        static let queueRowHeight: CGFloat = 56
        static let headerControlSize: CGFloat = 40
        static let headerActionsWidth: CGFloat = 92
        static let activeRowAnchorFraction: CGFloat = 1.0 / 3.0
        static let footerSpacerHeight: CGFloat = 100
        static let programmaticScrollBlockDuration: TimeInterval = 1.0
        static let maxVisibleHistoryTracks = 3
        static let maxVisibleQueueTracks = 10
        static let footerRowHeight: CGFloat = 44
        static let queueRowInsets = UIEdgeInsets(top: 6, left: horizontalInset, bottom: 6, right: horizontalInset)
        static let headerMargins = NSDirectionalEdgeInsets(top: 0, leading: horizontalInset, bottom: 0, trailing: horizontalInset)
    }

    var onToggleShuffle: () -> Void = {}
    var onCycleRepeatMode: () -> Void = {}
    var onSelectQueueTrack: (NowPlayingQueueTrackSelection) -> Void = { _ in }
    var onRemoveQueueTrack: (Int) -> Void = { _ in }
    var onRestartCurrentTrack: () -> Void = {}
    var onPlayFromHere: (Int) -> Void = { _ in }
    var onPlayNext: (PlaybackTrack) -> Void = { _ in }

    let queueTableView = UITableView(frame: .zero, style: .plain).then {
        $0.backgroundColor = .clear
        $0.clipsToBounds = false
        $0.allowsSelection = true
        $0.contentInset = UIEdgeInsets(
            top: Layout.verticalInset,
            left: 0,
            bottom: Layout.verticalInset,
            right: 0,
        )
        $0.scrollIndicatorInsets = UIEdgeInsets(
            top: Layout.verticalInset,
            left: 0,
            bottom: Layout.verticalInset,
            right: 0,
        )
        $0.separatorStyle = .none
        $0.showsVerticalScrollIndicator = false
        $0.contentInsetAdjustmentBehavior = .never
        $0.insetsContentViewsToSafeArea = false
        $0.rowHeight = Layout.queueRowHeight
        $0.sectionFooterHeight = 0
        $0.register(
            AmSongCell.self,
            forCellReuseIdentifier: AmSongCell.reuseID,
        )
        $0.register(
            NowPlayingQueueHeaderCell.self,
            forCellReuseIdentifier: NowPlayingQueueHeaderCell.reuseID,
        )
        $0.register(
            NowPlayingQueueEmptyCell.self,
            forCellReuseIdentifier: NowPlayingQueueEmptyCell.reuseID,
        )
        $0.register(
            NowPlayingQueueFooterCell.self,
            forCellReuseIdentifier: NowPlayingQueueFooterCell.reuseID,
        )
        if #available(iOS 15.0, *) {
            $0.sectionHeaderTopPadding = 0
        }
    }

    var historyTracks: [NowPlayingQueueDisplayTrack] = []
    var queueTracks: [NowPlayingQueueDisplayTrack] = []
    var playerIndex: Int?
    var fullQueueTracks: [PlaybackTrack] = []
    var fullQueuePlayerIndex: Int?
    var repeatMode: RepeatMode = .off
    var isShuffleFeedbackActive = false
    var hasAppliedInitialSnapshot = false
    var pendingAutoScrollToQueueStart = false
    var needsInitialAutoScrollOnPresent = true
    var isProgramaticScrollBlocked: Date = .distantPast
    var pendingContextMenuRemoval: Int?
    var pendingProgrammaticScrollRetry: DispatchWorkItem?
    let headerSpacerView = UIView()
    let footerSpacerView = UIView()
    lazy var dataSource = makeDataSource()
    private var cancellables: Set<AnyCancellable> = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        queueTableView.delegate = self
        headerSpacerView.backgroundColor = .clear
        footerSpacerView.backgroundColor = .clear
        headerSpacerView.frame = CGRect(x: 0, y: 0, width: 1, height: Layout.headerSpacerHeight)
        footerSpacerView.frame = CGRect(x: 0, y: 0, width: 1, height: Layout.footerSpacerHeight)
        queueTableView.tableHeaderView = headerSpacerView
        queueTableView.tableFooterView = footerSpacerView
        addSubview(queueTableView)

        queueTableView.snp.makeConstraints { make in
            make.top.bottom.equalToSuperview()
            make.leading.trailing.equalToSuperview().inset(16)
        }

        updateQueue(queue: [], playerIndex: nil, repeatMode: .off)

        ConfigurableKit.publisher(
            forKey: AppPreferences.cleanSongTitleKey, type: Bool.self,
        )
        .dropFirst()
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in self?.queueTableView.reloadData() }
        .store(in: &cancellables)
    }

    deinit {
        pendingProgrammaticScrollRetry?.cancel()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateSpacerFramesIfNeeded()
        performPendingAutoScrollIfNeeded(animated: true)
    }

    func updateQueue(
        queue: [PlaybackTrack],
        playerIndex: Int?,
        repeatMode: RepeatMode,
        animatingDifferences: Bool = false,
    ) {
        let previousHistoryTracks = historyTracks
        let previousQueueTracks = queueTracks
        let previousPlayerIndex = self.playerIndex
        let previousRepeatMode = self.repeatMode
        fullQueueTracks = queue
        fullQueuePlayerIndex = playerIndex
        let partitionedTracks = makeDisplayTracks(queue: queue, playerIndex: playerIndex)
        let didHistoryIdentityChange = previousHistoryTracks.map(\.identifier) != partitionedTracks.history.map(\.identifier)
        let didQueueIdentityChange = previousQueueTracks.map(\.identifier) != partitionedTracks.queue.map(\.identifier)
        let didTrackContentChange = previousHistoryTracks != partitionedTracks.history
            || previousQueueTracks != partitionedTracks.queue
        let didPlayerIndexChange = previousPlayerIndex != playerIndex
        let didRepeatModeChange = previousRepeatMode != repeatMode

        historyTracks = partitionedTracks.history
        queueTracks = partitionedTracks.queue
        self.playerIndex = playerIndex
        self.repeatMode = repeatMode

        AppLog.info(
            self,
            "queue refresh apply total=\(queue.count) history=\(historyTracks.count) upcoming=\(queueTracks.count) playerIndex=\(nowPlayingLogIndex(playerIndex)) repeatMode=\(String(describing: repeatMode)) identityChanged=\(didHistoryIdentityChange || didQueueIdentityChange) contentChanged=\(didTrackContentChange) playerChanged=\(didPlayerIndexChange) repeatChanged=\(didRepeatModeChange) animate=\(animatingDifferences)",
        )

        if didPlayerIndexChange {
            pendingAutoScrollToQueueStart = true
            if hasAppliedInitialSnapshot {
                blockProgrammaticScroll()
            }
        }

        guard didHistoryIdentityChange || didQueueIdentityChange || didTrackContentChange || didPlayerIndexChange else {
            if didRepeatModeChange {
                refreshQueueControlsCell()
            }
            performPendingAutoScrollIfNeeded(animated: false)
            return
        }

        applyQueueSnapshot(
            animatingDifferences: animatingDifferences && !didPlayerIndexChange && (didHistoryIdentityChange || didQueueIdentityChange),
            interfaceAnimated: animatingDifferences && didPlayerIndexChange && (didHistoryIdentityChange || didQueueIdentityChange),
            reconfiguredItems: reconfiguredItemIdentifiers(
                didTrackContentChange: didTrackContentChange,
                previousPlayerIndex: previousPlayerIndex,
                currentPlayerIndex: playerIndex,
            ),
        )
    }

    func setShuffleFeedbackActive(_ isActive: Bool) {
        guard isShuffleFeedbackActive != isActive else {
            return
        }
        isShuffleFeedbackActive = isActive
        refreshQueueControlsCell()
    }
}

// MARK: - NowPlayingQueueHeaderCell

final class NowPlayingQueueHeaderCell: TableBaseCell {
    static let reuseID = "NowPlayingQueueHeaderCell"

    private let buttonFeedbackGenerator = UIImpactFeedbackGenerator(style: .light)

    private enum Palette {
        static let activeForeground = UIColor.white
        static let inactiveForeground = UIColor.white.withAlphaComponent(0.58)
        static let activeBackground = UIColor.white.withAlphaComponent(0.18)
        static let inactiveBackground = UIColor.white.withAlphaComponent(0.05)
        static let activeBorder = UIColor.white.withAlphaComponent(0.32)
        static let inactiveBorder = UIColor.white.withAlphaComponent(0.12)
    }

    private let titleLabel = UILabel().then {
        $0.font = UIFontMetrics(forTextStyle: .title2).scaledFont(
            for: .systemFont(ofSize: 24, weight: .bold),
        )
        $0.adjustsFontForContentSizeCategory = true
        $0.textColor = UIColor.white.withAlphaComponent(0.92)
    }

    private let shuffleButton = UIButton(type: .system)
    private let repeatButton = UIButton(type: .system)
    private lazy var actionsStack = UIStackView(arrangedSubviews: [shuffleButton, repeatButton]).then {
        $0.axis = .horizontal
        $0.alignment = .center
        $0.spacing = 12
    }

    private var actionsWidthConstraint: Constraint?
    private var onShuffleTap: () -> Void = {}
    private var onRepeatTap: () -> Void = {}
    private var isShuffleFeedbackActive = false

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        contentView.directionalLayoutMargins = NowPlayingListSectionView.Layout.headerMargins

        contentView.addSubview(titleLabel)
        contentView.addSubview(actionsStack)

        titleLabel.snp.makeConstraints { make in
            make.leading.equalTo(contentView.layoutMarginsGuide.snp.leading)
            make.centerY.equalToSuperview()
            make.height.equalTo(NowPlayingListSectionView.Layout.headerControlSize)
            make.trailing.lessThanOrEqualTo(actionsStack.snp.leading).offset(-12)
        }

        actionsStack.snp.makeConstraints { make in
            make.trailing.equalTo(contentView.layoutMarginsGuide.snp.trailing)
            make.centerY.equalToSuperview()
            make.height.equalTo(NowPlayingListSectionView.Layout.headerControlSize)
            actionsWidthConstraint = make.width.equalTo(NowPlayingListSectionView.Layout.headerActionsWidth).constraint
        }

        for button in [shuffleButton, repeatButton] {
            button.snp.makeConstraints { make in
                make.size.equalTo(NowPlayingListSectionView.Layout.headerControlSize)
            }
            button.addTarget(self, action: #selector(handleTap(_:)), for: .touchUpInside)
        }

        shuffleButton.tag = 1
        repeatButton.tag = 2
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        titleLabel.text = nil
        onShuffleTap = {}
        onRepeatTap = {}
        isShuffleFeedbackActive = false
        actionsStack.isHidden = true
        actionsWidthConstraint?.update(offset: 0)
        shuffleButton.alpha = 1
    }

    func configure(title: String) {
        titleLabel.text = title
        onShuffleTap = {}
        onRepeatTap = {}
        isShuffleFeedbackActive = false
        actionsStack.isHidden = true
        actionsWidthConstraint?.update(offset: 0)
    }

    func configure(
        title: String,
        repeatMode: RepeatMode,
        isShuffleFeedbackActive: Bool,
        onShuffleTap: @escaping () -> Void,
        onRepeatTap: @escaping () -> Void,
    ) {
        titleLabel.text = title
        self.onShuffleTap = onShuffleTap
        self.onRepeatTap = onRepeatTap
        actionsStack.isHidden = false
        actionsWidthConstraint?.update(offset: NowPlayingListSectionView.Layout.headerActionsWidth)

        let repeatSymbol = switch repeatMode {
        case .off, .queue:
            "repeat"
        case .track:
            "repeat.1"
        }

        let shouldAnimateShuffleFeedback = self.isShuffleFeedbackActive == false
            && isShuffleFeedbackActive
        self.isShuffleFeedbackActive = isShuffleFeedbackActive

        applyConfiguration(
            to: shuffleButton,
            symbolName: "shuffle",
            isActive: isShuffleFeedbackActive,
        )
        applyConfiguration(
            to: repeatButton,
            symbolName: repeatSymbol,
            isActive: repeatMode != .off,
        )

        guard shouldAnimateShuffleFeedback else {
            return
        }
        animateShuffleFeedback()
    }

    @objc private func handleTap(_ sender: UIButton) {
        buttonFeedbackGenerator.impactOccurred()
        switch sender.tag {
        case 1:
            onShuffleTap()
        case 2:
            onRepeatTap()
        default:
            break
        }
    }

    private func applyConfiguration(
        to button: UIButton,
        symbolName: String,
        isActive: Bool,
    ) {
        var configuration = UIButton.Configuration.plain()
        configuration.baseForegroundColor = isActive ? Palette.activeForeground : Palette.inactiveForeground
        configuration.image = UIImage(
            systemName: symbolName,
            withConfiguration: UIImage.SymbolConfiguration(
                pointSize: isActive ? 16 : 15,
                weight: isActive ? .bold : .semibold,
            ),
        )
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
        configuration.background.cornerRadius = 12
        configuration.background.backgroundColor = isActive
            ? Palette.activeBackground
            : Palette.inactiveBackground
        configuration.background.strokeColor = isActive
            ? Palette.activeBorder
            : Palette.inactiveBorder
        configuration.background.strokeWidth = isActive ? 1.2 : 1
        button.configuration = configuration
    }

    private func animateShuffleFeedback() {
        guard window != nil else {
            return
        }

        shuffleButton.layer.removeAnimation(forKey: "queueShuffleFade")
        shuffleButton.alpha = 1

        InterfaceAnimate.keyframeAnimate(duration: 0.26) {
            UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.5) {
                self.shuffleButton.alpha = 0.35
            }
            UIView.addKeyframe(withRelativeStartTime: 0.5, relativeDuration: 0.5) {
                self.shuffleButton.alpha = 1
            }
        }
    }
}
