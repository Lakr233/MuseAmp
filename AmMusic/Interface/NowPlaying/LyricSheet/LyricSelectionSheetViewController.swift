import SnapKit
import Then
import UIKit

final class LyricSelectionSheetViewController: UIViewController {
    private enum Animation {
        static let duration: TimeInterval = 1.0
        static let damping: CGFloat = 1.05
        static let initialVelocity: CGFloat = 0.75
    }

    private let lyrics: [String]
    private let initialActiveIndex: Int?
    private let tableView = UITableView(frame: .zero, style: .plain).then {
        $0.backgroundColor = .clear
        $0.separatorStyle = .none
        $0.rowHeight = UITableView.automaticDimension
        $0.estimatedRowHeight = 56
        $0.allowsSelection = true
        $0.allowsMultipleSelection = true
        $0.allowsMultipleSelectionDuringEditing = true
    }

    private lazy var dataSource = makeDataSource()

    init(lyrics: [String], activeIndex: Int?) {
        self.lyrics = lyrics
        initialActiveIndex = activeIndex
        super.init(nibName: nil, bundle: nil)
        title = String(localized: "Lyric")
        preferredContentSize = CGSize(width: 460, height: 560)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.largeTitleDisplayMode = .never
        configureTableView()
        applySnapshot()
        selectInitialActiveRow()
        updateNavigationItems()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        scrollToInitialActiveRow()
    }

    private func configureTableView() {
        tableView.delegate = self
        tableView.register(LyricSelectionCell.self, forCellReuseIdentifier: LyricSelectionCell.reuseIdentifier)

        view.addSubview(tableView)
        tableView.frame = view.bounds
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        tableView.setEditing(true, animated: false)
    }

    private func makeDataSource() -> EditableDataSource {
        EditableDataSource(tableView: tableView) { [weak self] tableView, indexPath, itemID in
            let cell = tableView.dequeueReusableCell(withIdentifier: LyricSelectionCell.reuseIdentifier, for: indexPath)
            if let lyricCell = cell as? LyricSelectionCell, let self {
                let text = lyrics.indices.contains(itemID) ? lyrics[itemID] : ""
                lyricCell.configure(text: text)
            }
            return cell
        }
    }

    private func applySnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<Int, Int>()
        snapshot.appendSections([0])
        snapshot.appendItems(Array(lyrics.indices), toSection: 0)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func selectInitialActiveRow() {
        guard let activeIndex = initialActiveIndex,
              lyrics.indices.contains(activeIndex)
        else { return }

        let indexPath = IndexPath(row: activeIndex, section: 0)
        tableView.selectRow(at: indexPath, animated: false, scrollPosition: .none)
    }

    private func scrollToInitialActiveRow() {
        guard let activeIndex = initialActiveIndex,
              lyrics.indices.contains(activeIndex)
        else { return }

        let indexPath = IndexPath(row: activeIndex, section: 0)
        let cellRect = tableView.rectForRow(at: indexPath)
        let topOffset = tableView.bounds.height / 3
        let targetY = cellRect.origin.y - topOffset
        let maxY = max(tableView.contentSize.height - tableView.bounds.height, 0)
        let clampedY = min(max(targetY, 0), maxY)
        tableView.setContentOffset(CGPoint(x: 0, y: clampedY), animated: false)
    }

    private func updateNavigationItems() {
        navigationItem.leftBarButtonItem = nil
        let accentColor = UIColor(named: "AccentColor") ?? .tintColor

        let hasSelection = !(tableView.indexPathsForSelectedRows?.isEmpty ?? true)
        if hasSelection {
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                image: UIImage(systemName: "doc.on.doc.fill"),
                style: .plain,
                target: self,
                action: #selector(copySelectedLyrics)
            ).then {
                $0.tintColor = accentColor
            }
        } else {
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                image: UIImage(systemName: "checkmark"),
                style: .done,
                target: self,
                action: #selector(dismissSheet)
            ).then {
                $0.tintColor = accentColor
            }
        }
    }

    private func selectedLyrics() -> [String] {
        guard let selectedIndexPaths = tableView.indexPathsForSelectedRows else { return [] }
        return selectedIndexPaths
            .sorted { $0.row < $1.row }
            .compactMap { indexPath in
                guard let itemID = dataSource.itemIdentifier(for: indexPath),
                      lyrics.indices.contains(itemID)
                else { return nil }
                return lyrics[itemID]
            }
    }

    @objc
    private func dismissSheet() {
        dismiss(animated: true)
    }

    @objc
    private func copySelectedLyrics() {
        let selectedLyrics = selectedLyrics()
        guard !selectedLyrics.isEmpty else { return }

        UIPasteboard.general.string = selectedLyrics.joined(separator: "\n")
        AppLog.info(self, "copySelectedLyrics count=\(selectedLyrics.count)")
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss(animated: true)
    }
}

extension LyricSelectionSheetViewController: UITableViewDelegate {
    func tableView(_: UITableView, shouldBeginMultipleSelectionInteractionAt _: IndexPath) -> Bool {
        true
    }

    func tableView(_: UITableView, didBeginMultipleSelectionInteractionAt _: IndexPath) {
        tableView.setEditing(true, animated: true)
    }

    func tableViewDidEndMultipleSelectionInteraction(_: UITableView) {
        updateNavigationItems()
    }

    func tableView(_: UITableView, didSelectRowAt _: IndexPath) {
        updateNavigationItems()
    }

    func tableView(_: UITableView, didDeselectRowAt _: IndexPath) {
        updateNavigationItems()
    }
}

private final class EditableDataSource: UITableViewDiffableDataSource<Int, Int> {
    override func tableView(_: UITableView, canEditRowAt _: IndexPath) -> Bool {
        true
    }
}

private final class LyricSelectionCell: UITableViewCell {
    static let reuseIdentifier = "LyricSelectionCell"

    private let lyricLabel = UILabel().then {
        $0.numberOfLines = 0
        $0.textColor = .label
        $0.font = UIFontMetrics(forTextStyle: .title3).scaledFont(
            for: .systemFont(ofSize: 22, weight: .semibold)
        )
        $0.adjustsFontForContentSizeCategory = true
    }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        contentView.addSubview(lyricLabel)

        lyricLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().inset(12)
            make.bottom.equalToSuperview().inset(12)
            make.leading.equalToSuperview().inset(20)
            make.trailing.equalToSuperview().inset(20)
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    func configure(text: String) {
        lyricLabel.text = text
    }
}
