import Combine
import SnapKit
import UIKit

@MainActor
final class LyricTimelineView: UIView {
    nonisolated enum Layout {
        static let activeLineAnchorFraction: CGFloat = 1.0 / 3.0
        static let topBlurFraction: CGFloat = activeLineAnchorFraction / 2.0
        static let bottomBlurFraction: CGFloat = 0.28
        static let activeLineHeightEstimate: CGFloat = LyricTimelineLineStyle.estimatedLineHeight
        static let autoScrollCooldown: TimeInterval = 2.0
        static let verticalSpacing: CGFloat = 18
        static let minimumHorizontalInset: CGFloat = 16
        static let topContentInset: CGFloat = 200
        static let bottomContentInset: CGFloat = 248
        static let userInteractionCooldown: TimeInterval = 1.0
    }

    nonisolated enum Item: Sendable, Equatable {
        case spacer(CGFloat)
        case message(String)
        case line(Int, String, Bool)
        case staticLine(Int, String)
    }

    let tableView: UITableView = {
        let tableView = UITableView(frame: UIScreen.main.bounds, style: .plain)
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.showsVerticalScrollIndicator = false
        tableView.contentInsetAdjustmentBehavior = .never
        tableView.insetsContentViewsToSafeArea = false
        tableView.alwaysBounceVertical = true
        tableView.allowsSelection = true
        tableView.delaysContentTouches = false
        tableView.canCancelContentTouches = true
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = LyricTimelineLineStyle.estimatedLineHeight + Layout.verticalSpacing
        return tableView
    }()

    let topBlurView: EdgeFadeBlurView = .init(direction: .blurredTopClearBottom)
    let bottomBlurView: EdgeFadeBlurView = .init(direction: .blurredBottomClearTop)

    private(set) var items: [Item] = []
    /// The timeline the visible items were built from. Tap/seek actions must
    /// use this exact instance: re-parsing lyrics from the cache can yield a
    /// different line set than what is rendered, breaking index-based seeks.
    var renderedTimeline: LyricTimeline?

    let environment: AppEnvironment
    lazy var lineMenuProvider: LyricLineMenuProvider = {
        let provider = LyricLineMenuProvider(playbackController: environment.playbackController)
        provider.onSelectAndCopy = { [weak self] lines, selectedIndex in
            self?.presentLyricSelectionSheet(lyrics: lines, activeIndex: selectedIndex)
        }
        return provider
    }()

    var cancellables: Set<AnyCancellable> = []
    let focusSubject = PassthroughSubject<Void, Never>()
    let interactionSubject = PassthroughSubject<Void, Never>()
    var userInteractionDeadline: Date = .distantPast

    var isProgrammaticScrollSuppressed: Bool {
        Date() < userInteractionDeadline
    }

    init(environment: AppEnvironment) {
        self.environment = environment
        super.init(frame: UIScreen.main.bounds)

        addSubview(tableView)
        addSubview(topBlurView)
        addSubview(bottomBlurView)

        tableView.register(LyricTimelineCell.self, forCellReuseIdentifier: String(describing: LyricTimelineCell.self))
        tableView.register(StaticLyricCell.self, forCellReuseIdentifier: String(describing: StaticLyricCell.self))
        tableView.register(LyricTimelineSpacerCell.self, forCellReuseIdentifier: String(describing: LyricTimelineSpacerCell.self))
        tableView.register(LyricTimelineMessageCell.self, forCellReuseIdentifier: String(describing: LyricTimelineMessageCell.self))

        tableView.dataSource = self
        tableView.delegate = self

        tableView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        topBlurView.snp.makeConstraints { make in
            make.top.equalToSuperview()
            make.leading.trailing.equalToSuperview()
            make.height.equalToSuperview().multipliedBy(Layout.topBlurFraction)
        }

        bottomBlurView.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.bottom.equalToSuperview()
            make.height.equalToSuperview().multipliedBy(Layout.bottomBlurFraction)
        }

        bindDataSource()
    }

    func applySnapshot(_ snapshot: Snapshot) {
        let newItems = snapshot.items

        let oldHadContent = items.contains { Self.isContentItem($0) }
        let newHasContent = newItems.contains { Self.isContentItem($0) }

        AppLog.verbose(self, "applySnapshot oldCount=\(items.count) newCount=\(newItems.count) oldHadContent=\(oldHadContent) newHasContent=\(newHasContent)")

        if oldHadContent, !newHasContent {
            AppLog.info(self, "applySnapshot fade-out branch oldCount=\(items.count)")
            items = newItems
            Interface.transition(
                with: tableView,
                duration: 0.25,
                options: [.transitionCrossDissolve, .allowUserInteraction],
                animations: { self.tableView.reloadData() },
            )
            return
        }

        if !oldHadContent, newHasContent {
            AppLog.info(self, "applySnapshot fade-in branch newCount=\(newItems.count)")
            items = newItems
            tableView.reloadData()
            tableView.layoutIfNeeded()
            animateContentFadeIn()
            return
        }

        let structureChanged = items.count != newItems.count
            || zip(items, newItems).contains { old, new in
                switch (old, new) {
                case (.spacer, .spacer), (.message, .message): false
                case let (.line(a, _, _), .line(b, _, _)): a != b
                case let (.staticLine(a, _), .staticLine(b, _)): a != b
                default: true
                }
            }

        if structureChanged {
            AppLog.info(self, "applySnapshot structure-changed reload oldCount=\(items.count) newCount=\(newItems.count)")
            items = newItems
            tableView.reloadData()
        } else {
            AppLog.verbose(self, "applySnapshot state-only update count=\(newItems.count)")
            items = newItems
            for cell in tableView.visibleCells {
                guard let indexPath = tableView.indexPath(for: cell) else { continue }
                let item = items[indexPath.row]
                if case let .line(_, _, isActive) = item,
                   let lyricCell = cell as? LyricTimelineCell
                {
                    lyricCell.applyActive(isActive)
                }
            }
        }
    }

    private func animateContentFadeIn() {
        let contentCells = tableView.visibleCells
            .compactMap { cell -> (Int, UITableViewCell)? in
                guard let indexPath = tableView.indexPath(for: cell) else { return nil }
                guard !(cell is LyricTimelineSpacerCell) else { return nil }
                return (indexPath.row, cell)
            }
            .sorted { $0.0 < $1.0 }

        for (order, (_, cell)) in contentCells.enumerated() {
            cell.alpha = 0
            Interface.animate(
                duration: 0.5,
                delay: Double(order) * 0.1,
                options: [.allowUserInteraction],
                animations: { cell.alpha = 1 },
            )
        }
    }

    private static func isContentItem(_ item: Item) -> Bool {
        switch item {
        case .spacer: false
        default: true
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }
}
