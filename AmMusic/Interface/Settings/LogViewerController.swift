//
//  LogViewerController.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import AlertController
import SnapKit
import SPIndicator
import UIKit

final class LogViewerController: UIViewController, UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating {
    private enum LogLevel: String, CaseIterable {
        case verbose
        case info
        case warning
        case error
        case critical

        var title: String {
            switch self {
            case .verbose:
                String(localized: "Verbose")
            case .info:
                String(localized: "Info")
            case .warning:
                String(localized: "Warning")
            case .error:
                String(localized: "Error")
            case .critical:
                String(localized: "Critical")
            }
        }
    }

    private struct LogLine {
        let timestamp: String
        let level: LogLevel
        let category: String
        let message: String

        var searchText: String {
            [timestamp, level.rawValue, category, message]
                .filter { !$0.isEmpty }
                .joined(separator: " | ")
        }
    }

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let searchController = UISearchController(searchResultsController: nil)

    private var allLines: [LogLine] = []
    private var filteredLines: [LogLine] = []

    private var selectedLevels = Set(LogLevel.allCases)
    private var selectedCategories: Set<String> = []
    private var allCategories: Set<String> = []

    private var isSearching: Bool {
        let text = searchController.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return searchController.isActive && !text.isEmpty
    }

    private var displayLines: [LogLine] {
        isSearching ? filteredLines : allLines
    }

    init() {
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "Logs")
        view.backgroundColor = .systemBackground

        setupSearchController()
        setupMenuButton()
        setupTableView()
        reload()
    }

    func updateSearchResults(for _: UISearchController) {
        let query = searchController.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !query.isEmpty else {
            filteredLines = []
            updateBackgroundView()
            tableView.reloadData()
            return
        }

        filteredLines = allLines.filter {
            $0.searchText.localizedCaseInsensitiveContains(query)
                || $0.message.localizedCaseInsensitiveContains(query)
                || $0.category.localizedCaseInsensitiveContains(query)
        }
        updateBackgroundView()
        tableView.reloadData()
        scrollToBottom()
    }

    func numberOfSections(in _: UITableView) -> Int {
        1
    }

    func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
        displayLines.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let identifier = "LogCell"
        let cell = tableView.dequeueReusableCell(withIdentifier: identifier) ?? UITableViewCell(
            style: .subtitle,
            reuseIdentifier: identifier,
        )

        let line = displayLines[indexPath.row]
        cell.textLabel?.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        cell.textLabel?.numberOfLines = 0
        cell.textLabel?.text = line.message
        cell.textLabel?.textColor = color(for: line.level)

        cell.detailTextLabel?.font = .monospacedSystemFont(ofSize: 9, weight: .regular)
        cell.detailTextLabel?.numberOfLines = 1
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.detailTextLabel?.text = line.timestamp.isEmpty
            ? line.category
            : "\(line.timestamp) · \(line.category)"
        cell.backgroundColor = .systemBackground
        cell.selectionStyle = .none
        return cell
    }
}

extension LogViewerController {
    func setupSearchController() {
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = String(localized: "Search logs...")
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = true
    }

    func setupMenuButton() {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "ellipsis.circle"), for: .normal)
        button.showsMenuAsPrimaryAction = true
        button.menu = createMenu()
        button.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: button)
    }

    func setupTableView() {
        tableView.dataSource = self
        tableView.delegate = self
        tableView.estimatedRowHeight = 60
        tableView.rowHeight = UITableView.automaticDimension
        tableView.separatorStyle = .singleLine
        tableView.backgroundColor = .systemBackground
        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    func createMenu() -> UIMenu {
        let levelMenu = UIMenu(
            title: String(localized: "Filter by Level"),
            image: UIImage(systemName: "slider.horizontal.3"),
            children: LogLevel.allCases.map { level in
                UIAction(
                    title: level.title,
                    image: selectedLevels.contains(level) ? UIImage(systemName: "checkmark") : nil,
                ) { [weak self] _ in
                    guard let self else { return }
                    toggleLevel(level)
                }
            },
        )

        let categoryMenu = UIMenu(
            title: String(localized: "Filter by Category"),
            image: UIImage(systemName: "tag"),
            children: buildCategoryActions(),
        )

        let refreshAction = UIAction(
            title: String(localized: "Refresh"),
            image: UIImage(systemName: "arrow.clockwise"),
        ) { [weak self] _ in
            guard let self else { return }
            reload()
        }

        let shareAction = UIAction(
            title: String(localized: "Share"),
            image: UIImage(systemName: "square.and.arrow.up"),
        ) { [weak self] _ in
            guard let self else { return }
            shareLog()
        }

        let clearAction = UIAction(
            title: String(localized: "Clear"),
            image: UIImage(systemName: "trash"),
            attributes: .destructive,
        ) { [weak self] _ in
            guard let self else { return }
            confirmClearLog()
        }

        return UIMenu(children: [
            levelMenu,
            categoryMenu,
            UIMenu(options: .displayInline, children: [refreshAction]),
            UIMenu(options: .displayInline, children: [shareAction, clearAction]),
        ])
    }

    func buildCategoryActions() -> [UIMenuElement] {
        guard !allCategories.isEmpty else {
            return [UIAction(title: String(localized: "No categories")) { _ in }]
        }

        var actions: [UIMenuElement] = [
            UIAction(
                title: String(localized: "All Categories"),
                image: selectedCategories.isEmpty ? UIImage(systemName: "checkmark") : nil,
            ) { [weak self] _ in
                guard let self else { return }
                selectedCategories.removeAll()
                applyFilters()
                updateMenu()
            },
        ]

        actions.append(contentsOf: allCategories.sorted().map { category in
            UIAction(
                title: category,
                image: selectedCategories.contains(category) ? UIImage(systemName: "checkmark") : nil,
            ) { [weak self] _ in
                guard let self else { return }
                toggleCategory(category)
            }
        })
        return actions
    }

    private func toggleLevel(_ level: LogLevel) {
        if selectedLevels.contains(level) {
            selectedLevels.remove(level)
        } else {
            selectedLevels.insert(level)
        }
        applyFilters()
        updateMenu()
    }

    func toggleCategory(_ category: String) {
        if selectedCategories.contains(category) {
            selectedCategories.remove(category)
        } else {
            selectedCategories.insert(category)
        }
        applyFilters()
        updateMenu()
    }

    func updateMenu() {
        guard let button = navigationItem.rightBarButtonItem?.customView as? UIButton else { return }
        button.menu = createMenu()
    }

    func reload() {
        applyFilters()
    }

    func applyFilters() {
        allLines = parseLogLines()
        if isSearching {
            updateSearchResults(for: searchController)
        } else {
            filteredLines = []
        }
        updateBackgroundView()
        tableView.reloadData()
        scrollToBottom()
    }

    private func parseLogLines() -> [LogLine] {
        let text = AppLog.currentLogContent()
        let rawLines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        var parsed: [LogLine] = []
        var currentCategory = "App"
        var categories = Set<String>()

        for rawLine in rawLines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if line.hasPrefix("["),
               line.hasSuffix("]"),
               !line.contains("|")
            {
                currentCategory = String(line.dropFirst().dropLast())
                categories.insert(currentCategory)
                continue
            }

            let parsedLine = parseDogLine(line, category: currentCategory)
            categories.insert(parsedLine.category)

            guard selectedLevels.contains(parsedLine.level) else { continue }
            if !selectedCategories.isEmpty, !selectedCategories.contains(parsedLine.category) {
                continue
            }
            parsed.append(parsedLine)
        }

        allCategories = categories
        return parsed
    }

    private func parseDogLine(_ line: String, category: String) -> LogLine {
        guard line.hasPrefix("* |") else {
            return LogLine(
                timestamp: "",
                level: .info,
                category: category,
                message: line,
            )
        }

        let body = String(line.dropFirst(3))
        let parts = body.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3 else {
            return LogLine(
                timestamp: "",
                level: .info,
                category: category,
                message: line,
            )
        }

        return LogLine(
            timestamp: parts[1].trimmingCharacters(in: .whitespacesAndNewlines),
            level: LogLevel(rawValue: parts[0].trimmingCharacters(in: .whitespacesAndNewlines)) ?? .info,
            category: category,
            message: parts[2].trimmingCharacters(in: .whitespacesAndNewlines),
        )
    }

    func updateBackgroundView() {
        guard displayLines.isEmpty else {
            tableView.backgroundView = nil
            return
        }

        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .body)
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        label.text = isSearching ? String(localized: "No matching logs.") : String(localized: "No logs yet.")
        tableView.backgroundView = label
    }

    func scrollToBottom() {
        guard !displayLines.isEmpty else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let indexPath = IndexPath(row: displayLines.count - 1, section: 0)
            tableView.scrollToRow(at: indexPath, at: .bottom, animated: false)
        }
    }

    func shareLog() {
        let files = AppLog.allLogFiles()
        let items: [Any] = files.isEmpty ? [AppLog.currentLogContent()] : files
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        present(controller, animated: true)
    }

    func confirmClearLog() {
        ConfirmationAlertPresenter.present(
            on: self,
            title: String(localized: "Clear Logs"),
            message: String(localized: "This removes all log output from the current file log store."),
            confirmTitle: String(localized: "Clear"),
        ) { [weak self] in
            self?.clearLog()
        }
    }

    func clearLog() {
        do {
            try AppLog.clearLogs()
            reload()
        } catch {
            AppLog.error(self, "clearLog - failed: \(error.localizedDescription)")
            SPIndicator.present(title: String(localized: "Clear Failed"), message: error.localizedDescription, preset: .error)
        }
    }

    private func color(for level: LogLevel) -> UIColor {
        switch level {
        case .verbose:
            .tertiaryLabel
        case .info:
            .label
        case .warning:
            .systemOrange
        case .error:
            .systemRed
        case .critical:
            .systemRed
        }
    }
}
