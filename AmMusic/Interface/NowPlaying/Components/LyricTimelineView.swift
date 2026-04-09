import SnapKit
import Then
import UIKit
import VariableBlur

enum LyricTimelineAnimation {
    static let initialRevealDuration: TimeInterval = 0.32
    static let initialRevealStagger: TimeInterval = 0.035
    static let outgoingFadeDuration: TimeInterval = 0.16
    static let outgoingFadeStagger: TimeInterval = 0.04
    static let plainRevealDuration: TimeInterval = 0.26
    static let plainRevealTranslationY: CGFloat = 12
    static let easeOutOptions: UIView.AnimationOptions = [
        .allowUserInteraction,
        .beginFromCurrentState,
        .curveEaseOut,
    ]
}

enum LyricTimelineLineStyle {
    static let textFont = UIFontMetrics(forTextStyle: .title2).scaledFont(
        for: .systemFont(ofSize: 28, weight: .bold)
    )
    static let activeAlpha: CGFloat = 1.0
    static let inactiveAlpha: CGFloat = 0.25
    static let tapHighlightCornerRadius: CGFloat = 14
    static let estimatedLineHeight = ceil(textFont.lineHeight)
}

// MARK: - LyricTimelineView

final class LyricTimelineView: UIView, UIGestureRecognizerDelegate {
    enum Layout {
        static let activeLineAnchorFraction: CGFloat = 1.0 / 3.0
        static let topBlurFraction: CGFloat = activeLineAnchorFraction / 2.0
        static let activeLineHeightEstimate: CGFloat = LyricTimelineLineStyle.estimatedLineHeight
        static let autoScrollCooldown: TimeInterval = 2.0
        static let verticalSpacing: CGFloat = 18
        static let minimumHorizontalInset: CGFloat = 16
    }

    enum Mode: Equatable {
        case message(String)
        case plain([String])
        case synced(LRCLyricsTimeline)
    }

    let tableView = UITableView(frame: .zero, style: .plain).then {
        $0.backgroundColor = .clear
        $0.separatorStyle = .none
        $0.showsVerticalScrollIndicator = false
        $0.contentInsetAdjustmentBehavior = .never
        $0.insetsContentViewsToSafeArea = false
        $0.alwaysBounceVertical = true
        $0.allowsSelection = false
        $0.delaysContentTouches = false
        $0.canCancelContentTouches = true
        $0.rowHeight = UITableView.automaticDimension
        $0.estimatedRowHeight = LyricTimelineLineStyle.estimatedLineHeight + Layout.verticalSpacing
    }

    let messageLabel = UILabel().then {
        $0.textColor = UIColor.white.withAlphaComponent(0.76)
        $0.font = UIFontMetrics(forTextStyle: .body).scaledFont(
            for: .systemFont(ofSize: 17, weight: .medium)
        )
        $0.textAlignment = .center
        $0.numberOfLines = 0
        $0.adjustsFontForContentSizeCategory = true
        $0.clipsToBounds = false
    }

    let topBlurView = VariableBlurUIView(
        maxBlurRadius: 2,
        direction: .blurredTopClearBottom
    ).then {
        $0.isUserInteractionEnabled = false
    }

    let bottomBlurView = VariableBlurUIView(
        maxBlurRadius: 2,
        direction: .blurredBottomClearTop
    ).then {
        $0.isUserInteractionEnabled = false
    }

    var mode: Mode = .message(String(localized: "No lyrics available"))
    var activeIndex: Int?
    var currentTime: TimeInterval = 0
    var isAnimationSuspended = false
    var shouldAnimateNextSyncedReveal = false
    var pendingAutoScrollToActiveLine = false
    var isAutoScrollInCooldown = false
    var isBlurHiddenByInteraction = false
    var lineTransitionSequence = 0
    weak var activeOutgoingTransitionOverlay: UIView?
    private var messageLeadingConstraint: Constraint?
    private var messageTrailingConstraint: Constraint?
    var cachedHorizontalInset: CGFloat = Layout.minimumHorizontalInset

    lazy var scrollTapGestureRecognizer = UITapGestureRecognizer(
        target: self,
        action: #selector(handleScrollViewTap(_:))
    )

    var onSelectLineTime: ((TimeInterval) -> Void)?
    var onCopyAllLyrics: (([String]) -> Void)?
    var onRequestManageLyrics: ((_ lyrics: [String], _ activeIndex: Int?) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(tableView)
        addSubview(topBlurView)
        addSubview(bottomBlurView)
        addSubview(messageLabel)

        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(LyricTimelineCell.self, forCellReuseIdentifier: LyricTimelineCell.reuseIdentifier)

        scrollTapGestureRecognizer.cancelsTouchesInView = false
        scrollTapGestureRecognizer.delegate = self
        scrollTapGestureRecognizer.require(toFail: tableView.panGestureRecognizer)
        tableView.addGestureRecognizer(scrollTapGestureRecognizer)

        tableView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        topBlurView.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.height.equalToSuperview().multipliedBy(Layout.topBlurFraction)
        }

        bottomBlurView.snp.makeConstraints { make in
            make.bottom.leading.trailing.equalToSuperview()
            make.height.equalToSuperview().multipliedBy(Layout.activeLineAnchorFraction)
        }

        messageLabel.snp.makeConstraints { make in
            messageLeadingConstraint = make.leading.equalToSuperview().offset(Layout.minimumHorizontalInset).priority(.high).constraint
            messageTrailingConstraint = make.trailing.equalToSuperview().offset(-Layout.minimumHorizontalInset).priority(.high).constraint
            make.centerY.equalToSuperview()
        }

        apply(mode: .message(String(localized: "No lyrics available")), currentTime: 0, animated: false)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        guard bounds.width > 0 else {
            return
        }

        let readableFrame = readableContentGuide.layoutFrame
        let leadingInset = max(readableFrame.minX - bounds.minX, Layout.minimumHorizontalInset)
        let trailingInset = max(bounds.maxX - readableFrame.maxX, Layout.minimumHorizontalInset)

        messageLeadingConstraint?.update(offset: leadingInset)
        messageTrailingConstraint?.update(offset: -trailingInset)

        let newInset = max(leadingInset, trailingInset)
        if abs(cachedHorizontalInset - newInset) > 0.5 {
            cachedHorizontalInset = newInset
            tableView.reloadData()
        }

        updateTableViewInsets()
    }

    func setAnimationSuspended(_ suspended: Bool) {
        guard isAnimationSuspended != suspended else {
            return
        }

        isAnimationSuspended = suspended
        if suspended {
            stopTransientAnimations()
            return
        }

        syncVisibleState(animated: false)
    }

    func update(text: String?, isLoading: Bool, currentTime: TimeInterval) {
        if isLoading {
            apply(mode: .message(String(localized: "Loading lyrics...")), currentTime: currentTime, animated: false)
            return
        }

        let normalizedText = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let normalizedText, !normalizedText.isEmpty else {
            apply(mode: .message(String(localized: "No lyrics available")), currentTime: currentTime, animated: false)
            return
        }

        let timeline = LRCLyricsTimeline(lrc: normalizedText)
        if timeline.lines.isEmpty {
            let lines = normalizedText
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            apply(
                mode: lines.isEmpty ? .message(String(localized: "No lyrics available")) : .plain(lines),
                currentTime: currentTime,
                animated: false
            )
            return
        }

        apply(mode: .synced(timeline), currentTime: currentTime, animated: false)
    }

    func updateCurrentTime(_ currentTime: TimeInterval) {
        self.currentTime = currentTime
        syncVisibleState(animated: window != nil)
    }
}

// MARK: - Mode helpers

extension LyricTimelineView.Mode {
    var logDescription: String {
        switch self {
        case let .message(message):
            "message[\(message)]"
        case let .plain(lines):
            "plain[count=\(lines.count)]"
        case let .synced(timeline):
            "synced[count=\(timeline.lines.count)]"
        }
    }

    var isMessage: Bool {
        if case .message = self { return true }
        return false
    }

    var hasLineContent: Bool {
        switch self {
        case .message: false
        case .plain, .synced: true
        }
    }

    var lineCount: Int {
        switch self {
        case .message: 0
        case let .plain(lines): lines.count
        case let .synced(timeline): timeline.lines.count
        }
    }
}

// MARK: - UITableViewDataSource & UITableViewDelegate

extension LyricTimelineView: UITableViewDataSource, UITableViewDelegate {
    func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
        mode.lineCount
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: LyricTimelineCell.reuseIdentifier, for: indexPath) as! LyricTimelineCell
        let row = indexPath.row

        switch mode {
        case .message:
            break
        case let .plain(lines):
            cell.configure(
                text: lines[row],
                horizontalInset: cachedHorizontalInset,
                state: .inapplicable,
                seekTime: nil,
                onTap: nil
            )
        case let .synced(timeline):
            let line = timeline.lines[row]
            let state = stateForLine(at: row, activeIndex: activeIndex)
            let isLeadingPaddingLine = isSyntheticLeadingPaddingLine(at: row, in: timeline)
            cell.configure(
                text: line.text,
                horizontalInset: cachedHorizontalInset,
                state: state,
                seekTime: isLeadingPaddingLine ? nil : line.time
            ) { [weak self] selectedTime in
                self?.beginBlurHideCooldown()
                self?.onSelectLineTime?(selectedTime)
            }
        }

        return cell
    }

    func tableView(
        _: UITableView,
        contextMenuConfigurationForRowAt indexPath: IndexPath,
        point _: CGPoint
    ) -> UIContextMenuConfiguration? {
        if case let .synced(timeline) = mode,
           isSyntheticLeadingPaddingLine(at: indexPath.row, in: timeline)
        {
            return nil
        }

        guard let menu = makeLyricContextMenu() else { return nil }
        return UIContextMenuConfiguration(
            identifier: indexPath as NSIndexPath,
            previewProvider: nil
        ) { _ in menu }
    }

    func scrollViewWillBeginDragging(_: UIScrollView) {
        beginBlurHideCooldown()
    }

    func scrollViewDidEndDragging(_: UIScrollView, willDecelerate _: Bool) {}

    func scrollViewDidEndDecelerating(_: UIScrollView) {}

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating else {
            return
        }

        beginAutoScrollCooldown()
        beginBlurHideCooldown()
    }
}

// MARK: - UIGestureRecognizerDelegate

extension LyricTimelineView {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if gestureRecognizer === scrollTapGestureRecognizer {
            return !(touch.view is LyricTimelineCell)
        }
        return true
    }
}
