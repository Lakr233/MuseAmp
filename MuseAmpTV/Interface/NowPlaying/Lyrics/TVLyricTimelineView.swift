import Combine
import SnapKit
import UIKit

@MainActor
final class TVLyricTimelineView: UIView {
    nonisolated enum Layout {
        static let userInteractionCooldown: TimeInterval = 1.0
        static let activeLineAnchorFraction: CGFloat = 1.0 / 3.0
        static let topFadeFraction: CGFloat = TVNowPlayingLayout.lyricTopFadeFraction
        static let bottomFadeFraction: CGFloat = TVNowPlayingLayout.lyricBottomFadeFraction
        static let verticalSpacing: CGFloat = TVNowPlayingLayout.spacing16
        static let topContentInset: CGFloat = TVNowPlayingLayout.lyricSpacerHeight
        static let bottomContentInset: CGFloat = TVNowPlayingLayout.lyricSpacerHeight
    }

    nonisolated enum Item: Sendable, Equatable {
        case spacer(CGFloat)
        case message(String)
        case line(Int, String, Bool)
        case staticLine(Int, String)
    }

    nonisolated struct Snapshot: Sendable, Equatable {
        let items: [Item]
    }

    nonisolated enum LyricsPhase: Sendable, Equatable {
        case pending
        case loaded(ParsedLyrics)
    }

    nonisolated struct ParsedLyrics: Sendable, Equatable {
        let lines: [String]
        let timeline: TVLyricTimeline?

        static let empty = ParsedLyrics(lines: [], timeline: nil)
    }

    private let tableView: UITableView = {
        let tableView = UITableView(frame: UIScreen.main.bounds, style: .plain)
        tableView.backgroundColor = .clear
        tableView.showsVerticalScrollIndicator = false
        tableView.contentInsetAdjustmentBehavior = .never
        tableView.insetsContentViewsToSafeArea = false
        tableView.alwaysBounceVertical = false
        tableView.allowsSelection = false
        tableView.isUserInteractionEnabled = false
        tableView.delaysContentTouches = false
        tableView.canCancelContentTouches = true
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = TVLyricLineStyle.estimatedLineHeight + Layout.verticalSpacing
        return tableView
    }()

    private let topFadeView = TVLyricEdgeFadeView(direction: .topFade)
    private let bottomFadeView = TVLyricEdgeFadeView(direction: .bottomFade)

    private var items: [Item] = []
    private var parsedLyrics: ParsedLyrics = .empty
    private var currentTime: TimeInterval = 0
    private var lastFocusedActiveRow: Int?
    private var cancellables: Set<AnyCancellable> = []
    let interactionSubject = PassthroughSubject<Void, Never>()
    let focusSubject = PassthroughSubject<Void, Never>()
    var userInteractionDeadline: Date = .distantPast

    var isProgrammaticScrollSuppressed: Bool {
        Date() < userInteractionDeadline
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        addSubview(tableView)
        addSubview(topFadeView)
        addSubview(bottomFadeView)

        tableView.dataSource = self
        tableView.delegate = self
        bindInteraction()
        tableView.register(TVLyricTimelineCell.self, forCellReuseIdentifier: String(describing: TVLyricTimelineCell.self))
        tableView.register(TVStaticLyricCell.self, forCellReuseIdentifier: String(describing: TVStaticLyricCell.self))
        tableView.register(TVLyricTimelineSpacerCell.self, forCellReuseIdentifier: String(describing: TVLyricTimelineSpacerCell.self))
        tableView.register(TVLyricTimelineMessageCell.self, forCellReuseIdentifier: String(describing: TVLyricTimelineMessageCell.self))

        tableView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        topFadeView.snp.makeConstraints { make in
            make.leading.trailing.top.equalToSuperview()
            make.height.equalToSuperview().multipliedBy(Layout.topFadeFraction)
        }
        bottomFadeView.snp.makeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview()
            make.height.equalToSuperview().multipliedBy(Layout.bottomFadeFraction)
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    // MARK: - Public API

    func update(text: String?, isLoading: Bool, currentTime: TimeInterval) {
        self.currentTime = currentTime
        lastFocusedActiveRow = nil

        if isLoading {
            parsedLyrics = .empty
            applySnapshot(buildSnapshot(phase: .pending, currentTime: currentTime))
            return
        }

        let normalizedText = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let normalizedText, !normalizedText.isEmpty else {
            parsedLyrics = .empty
            applySnapshot(buildSnapshot(phase: .loaded(.empty), currentTime: currentTime))
            return
        }

        parsedLyrics = Self.parseLyrics(from: normalizedText)
        let snapshot = buildSnapshot(phase: .loaded(parsedLyrics), currentTime: currentTime)
        applySnapshot(snapshot)
        if parsedLyrics.timeline != nil {
            focusCurrentLine()
        }
    }

    func updateCurrentTime(_ currentTime: TimeInterval) {
        self.currentTime = currentTime
        guard parsedLyrics.timeline != nil else { return }
        applySnapshot(buildSnapshot(phase: .loaded(parsedLyrics), currentTime: currentTime))
        focusSubject.send()
    }

    func scrollUpOneLine() {
        interactionSubject.send()
        let lineHeight = TVLyricLineStyle.estimatedLineHeight + Layout.verticalSpacing
        let target = clampedOffsetY(tableView.contentOffset.y - lineHeight)
        Interface.smoothSpringAnimate {
            self.tableView.setContentOffset(CGPoint(x: 0, y: target), animated: false)
            self.layoutIfNeeded()
        }
    }

    func scrollDownOneLine() {
        interactionSubject.send()
        let lineHeight = TVLyricLineStyle.estimatedLineHeight + Layout.verticalSpacing
        let target = clampedOffsetY(tableView.contentOffset.y + lineHeight)
        Interface.smoothSpringAnimate {
            self.tableView.setContentOffset(CGPoint(x: 0, y: target), animated: false)
            self.layoutIfNeeded()
        }
    }

    private func bindInteraction() {
        interactionSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self else { return }
                userInteractionDeadline = Date().addingTimeInterval(Layout.userInteractionCooldown)
                Interface.animate(duration: 0.25) {
                    self.topFadeView.alpha = 0
                    self.bottomFadeView.alpha = 0
                }
            }
            .store(in: &cancellables)

        interactionSubject
            .delay(for: .seconds(Layout.userInteractionCooldown + 0.1), scheduler: DispatchQueue.main)
            .sink { [weak self] in
                guard let self else { return }
                guard !isProgrammaticScrollSuppressed else { return }
                Interface.animate(duration: 1.0) {
                    self.topFadeView.alpha = 1
                    self.bottomFadeView.alpha = 1
                }
            }
            .store(in: &cancellables)

        focusSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.focusCurrentLine()
            }
            .store(in: &cancellables)
    }

    // MARK: - Snapshot Application

    private func applySnapshot(_ snapshot: Snapshot) {
        let newItems = snapshot.items

        let oldHadContent = items.contains { Self.isContentItem($0) }
        let newHasContent = newItems.contains { Self.isContentItem($0) }

        if oldHadContent, !newHasContent {
            items = newItems
            UIView.transition(
                with: tableView,
                duration: 0.25,
                options: [.transitionCrossDissolve, .allowUserInteraction],
                animations: { self.tableView.reloadData() },
                completion: nil,
            )
            return
        }

        if !oldHadContent, newHasContent {
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
            items = newItems
            tableView.reloadData()
        } else {
            items = newItems
            for cell in tableView.visibleCells {
                guard let indexPath = tableView.indexPath(for: cell) else { continue }
                let item = items[indexPath.row]
                if case let .line(_, _, isActive) = item,
                   let lyricCell = cell as? TVLyricTimelineCell
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
                guard !(cell is TVLyricTimelineSpacerCell) else { return nil }
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

    // MARK: - Snapshot Building

    private func buildSnapshot(phase: LyricsPhase, currentTime: TimeInterval) -> Snapshot {
        switch phase {
        case .pending:
            return Snapshot(items: [
                .spacer(Layout.topContentInset),
                .spacer(Layout.bottomContentInset),
            ])
        case let .loaded(lyrics):
            guard !lyrics.lines.isEmpty else {
                return Snapshot(items: [
                    .spacer(Layout.topContentInset),
                    .message(String(localized: "No lyrics available")),
                    .spacer(Layout.bottomContentInset),
                ])
            }

            var items: [Item] = [.spacer(Layout.topContentInset)]
            if let timeline = lyrics.timeline {
                let activeIndex = timeline.progress(at: currentTime)?.index
                for (index, text) in lyrics.lines.enumerated() {
                    items.append(.line(index, text, index == activeIndex))
                }
            } else {
                for (index, text) in lyrics.lines.enumerated() {
                    items.append(.staticLine(index, text))
                }
            }
            items.append(.spacer(Layout.bottomContentInset))
            return Snapshot(items: items)
        }
    }

    nonisolated static func parseLyrics(from lyricsText: String?) -> ParsedLyrics {
        guard let trimmed = lyricsText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else {
            return .empty
        }

        let timeline = TVLyricTimeline(lrc: trimmed)

        if !timeline.lines.isEmpty {
            return ParsedLyrics(lines: timeline.lines.map(\.text), timeline: timeline)
        }

        let plainLines = trimmed
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        return ParsedLyrics(lines: plainLines, timeline: nil)
    }

    // MARK: - Scroll Helpers

    private func focusCurrentLine() {
        guard !isProgrammaticScrollSuppressed else { return }
        let animated = window != nil
        guard tableView.bounds.height > 0 else { return }

        guard let activeRow = items.firstIndex(where: {
            if case let .line(_, _, isActive) = $0 {
                return isActive
            }
            return false
        }) else { return }

        guard activeRow != lastFocusedActiveRow || tableView.contentOffset == .zero else { return }
        lastFocusedActiveRow = activeRow

        layoutIfNeeded()

        let indexPath = IndexPath(row: activeRow, section: 0)
        let cellRect = tableView.rectForRow(at: indexPath)
        let targetY = cellRect.midY - tableView.bounds.height * Layout.activeLineAnchorFraction
        let maxY = tableView.contentSize.height - tableView.bounds.height
        let clampedY = min(max(targetY, 0), max(maxY, 0))

        guard abs(tableView.contentOffset.y - clampedY) > 5 else { return }

        if animated {
            Interface.smoothSpringAnimate {
                self.tableView.setContentOffset(CGPoint(x: 0, y: clampedY), animated: false)
                self.layoutIfNeeded()
            }
        } else {
            tableView.setContentOffset(CGPoint(x: 0, y: clampedY), animated: false)
        }
    }

    private func clampedOffsetY(_ offsetY: CGFloat) -> CGFloat {
        let minimum: CGFloat = 0
        let maximum = max(
            tableView.contentSize.height - tableView.bounds.height,
            minimum,
        )
        return min(max(offsetY, minimum), maximum)
    }
}

extension TVLyricTimelineView: UITableViewDataSource, UITableViewDelegate {
    func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
        items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let item = items[indexPath.row]
        switch item {
        case let .spacer(height):
            let cell = tableView.dequeueReusableCell(
                withIdentifier: String(describing: TVLyricTimelineSpacerCell.self),
                for: indexPath,
            ) as! TVLyricTimelineSpacerCell
            cell.configure(height: height)
            return cell
        case let .message(text):
            let cell = tableView.dequeueReusableCell(
                withIdentifier: String(describing: TVLyricTimelineMessageCell.self),
                for: indexPath,
            ) as! TVLyricTimelineMessageCell
            cell.configure(text: text)
            return cell
        case let .line(_, text, isActive):
            let cell = tableView.dequeueReusableCell(
                withIdentifier: String(describing: TVLyricTimelineCell.self),
                for: indexPath,
            ) as! TVLyricTimelineCell
            cell.configure(text: text, isActive: isActive)
            return cell
        case let .staticLine(_, text):
            let cell = tableView.dequeueReusableCell(
                withIdentifier: String(describing: TVStaticLyricCell.self),
                for: indexPath,
            ) as! TVStaticLyricCell
            cell.configure(text: text, isActive: true)
            return cell
        }
    }

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
}
