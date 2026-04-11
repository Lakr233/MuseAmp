//
//  SyncSongPickerViewController.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import AlertController
import AmMusicDatabaseKit
import SnapKit
import Then
import UIKit

final class SyncSongPickerViewController: UIViewController {
    nonisolated enum Section: Hashable {
        case main
    }

    let environment: AppEnvironment
    let tableView = UITableView(frame: .zero, style: .plain)
    let startButton = UIButton(type: .system)

    var dataSource: UITableViewDiffableDataSource<Section, String>!
    var allTracks: [AudioTrackRecord] = []
    var filteredTracks: [AudioTrackRecord] = []
    var tracksByID: [String: AudioTrackRecord] = [:]
    var selectedTrackIDs: Set<String> = []
    var searchTask: Task<Void, Never>?

    private var currentQuery = ""

    lazy var searchController = UISearchController(searchResultsController: nil).then {
        $0.searchResultsUpdater = self
        $0.obscuresBackgroundDuringPresentation = false
        $0.searchBar.placeholder = String(localized: "Search Local Library")
    }

    lazy var selectionToggleButton = UIBarButtonItem(
        title: String(localized: "Select All"),
        style: .plain,
        target: self,
        action: #selector(toggleSelection),
    )

    init(environment: AppEnvironment) {
        self.environment = environment
        super.init(nibName: nil, bundle: nil)
        title = String(localized: "Select Songs")
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    deinit {
        searchTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        configureNavigationBar()
        configureTableView()
        configureDataSource()
        configureStartButton()
        loadTracks()
    }

    var visibleTracks: [AudioTrackRecord] {
        currentQuery.isEmpty ? allTracks : filteredTracks
    }

    func applySnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<Section, String>()
        snapshot.appendSections([.main])
        snapshot.appendItems(visibleTracks.map(\.trackID))
        dataSource.apply(snapshot, animatingDifferences: view.window != nil)
        updateSelectionUI()
    }
}

private extension SyncSongPickerViewController {
    func configureNavigationBar() {
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        navigationItem.rightBarButtonItem = selectionToggleButton
    }

    func configureTableView() {
        tableView.delegate = self
        tableView.register(AmSongCell.self, forCellReuseIdentifier: AmSongCell.reuseID)
        tableView.tableFooterView = UIView()
        tableView.keyboardDismissMode = .onDrag

        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.top.left.right.equalToSuperview()
        }
    }

    func configureDataSource() {
        dataSource = UITableViewDiffableDataSource<Section, String>(
            tableView: tableView,
        ) { [weak self] (tableView: UITableView, indexPath: IndexPath, trackID: String) in
            guard let self,
                  let track = tracksByID[trackID],
                  let cell = tableView.dequeueReusableCell(
                      withIdentifier: AmSongCell.reuseID,
                      for: indexPath,
                  ) as? AmSongCell
            else {
                return UITableViewCell()
            }

            cell.configure(with: track)
            let cacheURL = environment.paths.artworkCacheURL(for: track.trackID)
            AmImageView.diskLoadQueue.async {
                guard FileManager.default.fileExists(atPath: cacheURL.path) else { return }
                DispatchQueue.main.async { [weak cell] in
                    cell?.loadArtwork(url: cacheURL)
                }
            }
            cell.accessoryType = selectedTrackIDs.contains(trackID) ? .checkmark : .none
            return cell
        }
    }

    func configureStartButton() {
        var configuration = UIButton.Configuration.filled()
        configuration.title = String(localized: "Start (0 selected)")
        configuration.cornerStyle = .large
        startButton.configuration = configuration
        startButton.addTarget(self, action: #selector(startTransfer), for: .touchUpInside)
        startButton.isEnabled = false

        view.addSubview(startButton)
        startButton.snp.makeConstraints { make in
            make.left.right.equalToSuperview().inset(16)
            make.top.equalTo(tableView.snp.bottom).offset(12)
            make.bottom.equalTo(view.safeAreaLayoutGuide).inset(12)
            make.height.equalTo(50)
        }

        tableView.snp.remakeConstraints { make in
            make.top.left.right.equalToSuperview()
            make.bottom.equalTo(startButton.snp.top).offset(-12)
        }
    }

    func loadTracks() {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            do {
                let database = environment.libraryDatabase
                let tracks = try await Task.detached(priority: .userInitiated) {
                    try database.allTracks().sorted {
                        if $0.title == $1.title {
                            return $0.artistName.localizedCaseInsensitiveCompare($1.artistName) == .orderedAscending
                        }
                        return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                    }
                }.value
                guard !tracks.isEmpty else {
                    showEmptyLibraryAlert()
                    return
                }
                allTracks = tracks
                tracksByID = Dictionary(uniqueKeysWithValues: tracks.map { ($0.trackID, $0) })
                applySnapshot()
            } catch {
                AppLog.error(self, "loadTracks failed: \(error.localizedDescription)")
            }
        }
    }

    func updateSelectionUI() {
        let visibleTrackIDs = Set(visibleTracks.map(\.trackID))
        let hasVisibleTracks = !visibleTrackIDs.isEmpty
        let allVisibleSelected = hasVisibleTracks && visibleTrackIDs.isSubset(of: selectedTrackIDs)
        selectionToggleButton.title = allVisibleSelected
            ? String(localized: "Deselect All")
            : String(localized: "Select All")

        var configuration = startButton.configuration ?? .filled()
        configuration.title = String(
            format: String(localized: "Start (%lld selected)"),
            selectedTrackIDs.count,
        )
        startButton.configuration = configuration
        startButton.isEnabled = !selectedTrackIDs.isEmpty
    }

    func updateFilter(query: String) {
        currentQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        searchTask?.cancel()

        guard !currentQuery.isEmpty else {
            filteredTracks = []
            applySnapshot()
            return
        }

        let needle = currentQuery.lowercased()
        let tracks = allTracks
        searchTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            let results = tracks.filter { track in
                [track.title, track.artistName, track.albumTitle]
                    .contains { $0.lowercased().contains(needle) }
            }
            guard !Task.isCancelled else {
                return
            }
            filteredTracks = results
            applySnapshot()
        }
    }

    func showEmptyLibraryAlert() {
        let alert = AlertViewController(
            title: String(localized: "No Songs Available"),
            message: String(localized: "Your local library is empty. Import songs first before sending."),
        ) { [weak self] context in
            context.addAction(title: String(localized: "OK"), attribute: .accent) {
                context.dispose {
                    self?.navigationController?.popViewController(animated: true)
                }
            }
        }
        present(alert, animated: true)
    }

    @objc func toggleSelection() {
        let visibleTrackIDs = Set(visibleTracks.map(\.trackID))
        guard !visibleTrackIDs.isEmpty else {
            return
        }

        if visibleTrackIDs.isSubset(of: selectedTrackIDs) {
            selectedTrackIDs.subtract(visibleTrackIDs)
        } else {
            selectedTrackIDs.formUnion(visibleTrackIDs)
        }
        applySnapshot()
    }

    @objc func startTransfer() {
        let selectedTracks = allTracks.filter { selectedTrackIDs.contains($0.trackID) }
        guard !selectedTracks.isEmpty else {
            return
        }

        navigationController?.pushViewController(
            SyncServerStatusViewController(
                tracks: selectedTracks,
                environment: environment,
            ),
            animated: true,
        )
    }
}

extension SyncSongPickerViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        updateFilter(query: searchController.searchBar.text ?? "")
    }
}
