//
//  PlaylistViewController.swift
//  MuseAmp
//
//  Created by @Lakr233 on 2026/04/11.
//

import AlertController
import MuseAmpDatabaseKit
import SnapKit
import Then
import UIKit

nonisolated enum PlaylistSection: Hashable {
    case playlists
    case searchResults
}

nonisolated enum PlaylistItem: Hashable {
    case playlist(UUID)
    case searchResult(UUID)
}

final class PlaylistDiffableDataSource: UITableViewDiffableDataSource<PlaylistSection, PlaylistItem> {
    var isSearchActiveProvider: (() -> Bool)?

    override func tableView(_: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        guard !(isSearchActiveProvider?() ?? false) else { return false }
        guard let item = itemIdentifier(for: indexPath) else { return false }
        if case PlaylistItem.playlist = item {
            return true
        }
        return false
    }
}

class PlaylistViewController: UIViewController {
    enum SortOption: String, CaseIterable {
        case name
        case trackCount
        case duration
        case recentlyModified
        case recentlyCreated

        var title: String {
            switch self {
            case .name:
                String(localized: "Sort by Name")
            case .trackCount:
                String(localized: "Sort by Track Count")
            case .duration:
                String(localized: "Sort by Duration")
            case .recentlyModified:
                String(localized: "Sort by Recently Modified")
            case .recentlyCreated:
                String(localized: "Sort by Recently Created")
            }
        }

        var imageName: String {
            switch self {
            case .name:
                "textformat.abc"
            case .trackCount:
                "number"
            case .duration:
                "timer"
            case .recentlyModified:
                "clock"
            case .recentlyCreated:
                "calendar"
            }
        }
    }

    let environment: AppEnvironment?
    let store: PlaylistStore
    let tableView = UITableView(frame: UIScreen.main.bounds, style: .plain)
    var sortOption: SortOption = AppPreferences.storedSortOption(
        forKey: AppPreferences.playlistsSortOptionKey,
        defaultValue: .recentlyModified,
    )
    var sortedPlaylists: [Playlist] = []
    private nonisolated(unsafe) var playlistsDidChangeObserver: NSObjectProtocol?
    lazy var playlistMenuProvider = PlaylistContextMenuProvider(
        playlistStore: store,
        viewController: self,
    )
    lazy var addToPlaylistMenuProvider = AddToPlaylistMenuProvider(
        playlistStore: store,
        viewController: self,
    )
    lazy var playlistTransferCoordinator: PlaylistTransferCoordinator = {
        let coordinator = PlaylistTransferCoordinator(
            viewController: self,
            playlistStore: store,
            environment: environment,
        )
        coordinator.onImportCompleted = { [weak self] _ in
            self?.reloadPlaylists(animated: false)
        }
        return coordinator
    }()

    lazy var addButton = UIBarButtonItem(
        image: UIImage(systemName: "plus"),
        menu: UIMenu(children: [
            UIAction(
                title: String(localized: "Custom Playlist"),
                image: UIImage(systemName: "text.badge.plus"),
            ) { [weak self] _ in self?.createCustomPlaylist() },
            UIMenu(
                title: String(localized: "Random Playlist"),
                image: UIImage(systemName: "shuffle"),
                children: [16, 25, 36, 64].map { count in
                    UIAction(
                        title: String(localized: "\(count) Songs"),
                    ) { [weak self] _ in self?.createRandomPlaylist(count: count) }
                },
            ),
        ]),
    ).then {
        $0.accessibilityIdentifier = "playlist.add"
    }

    lazy var finishSelectionButton = UIBarButtonItem(
        image: UIImage(systemName: "checkmark.circle"),
        style: .plain,
        target: self,
        action: #selector(finishSelectionTapped),
    )

    var dataSource: PlaylistDiffableDataSource!
    var playlistsByID: [UUID: Playlist] = [:]
    var searchResultsByID: [UUID: (playlist: Playlist, matchingSongNames: [String])] = [:]
    var orderedSearchResultIDs: [UUID] = []
    private var hasAppliedInitialSnapshot = false
    private var hasPreparedInitialData = false

    // MARK: - Search

    var currentQuery = ""
    var searchTask: Task<Void, Never>?

    var isSearchActive: Bool {
        searchController.isActive && !(searchController.searchBar.text?.isEmpty ?? true)
    }

    lazy var searchController = UISearchController(searchResultsController: nil).then {
        $0.searchResultsUpdater = self
        $0.obscuresBackgroundDuringPresentation = false
        $0.searchBar.placeholder = String(localized: "Search Local Playlists")
    }

    // MARK: - Empty States

    private let emptyStateView = EmptyStateView(
        icon: "music.note.list",
        title: String(localized: "No Playlists Yet"),
        subtitle: String(localized: "Tap + to create your first playlist"),
    )

    private let noResultsView = EmptyStateView(
        icon: "magnifyingglass",
        title: String(localized: "No Results"),
        subtitle: String(localized: "Try a different search term"),
    ).then { $0.isHidden = true }

    // MARK: - Lifecycle

    init(environment: AppEnvironment) {
        self.environment = environment
        store = environment.playlistStore
        super.init(nibName: nil, bundle: nil)
    }

    init(store: PlaylistStore) {
        environment = nil
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        if title == nil {
            title = String(localized: "Playlist")
        }
        navigationController?.navigationBar.prefersLargeTitles = true
        view.backgroundColor = .systemBackground

        configureTableView()
        configureDataSource()
        configureNavBar()
        configureEmptyState()
        observePlaylistChanges()
        prepareInitialDataIfNeeded()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard hasPreparedInitialData else {
            return
        }
        reloadPlaylists(animated: false)
    }

    deinit {
        searchTask?.cancel()
        if let playlistsDidChangeObserver {
            NotificationCenter.default.removeObserver(playlistsDidChangeObserver)
        }
    }

    // MARK: - Nav Bar

    private func configureNavBar() {
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true
        updateNavigationItems()
    }

    private func observePlaylistChanges() {
        playlistsDidChangeObserver = NotificationCenter.default.addObserver(
            forName: .playlistsDidChange,
            object: store,
            queue: .main,
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.reloadPlaylists()
            }
        }
    }

    private func createCustomPlaylist() {
        let alert = AlertInputViewController(
            title: "New Playlist",
            message: "Enter a name for your playlist.",
            placeholder: "Playlist Name",
            text: "",
        ) { [weak self] name in
            guard let self else { return }
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                AppLog.warning(self, "createCustomPlaylist empty name after trim, ignoring")
                return
            }
            store.createPlaylist(name: trimmed)
            reloadPlaylists()
        }
        present(alert, animated: true)
    }

    private func createRandomPlaylist(count: Int = 25) {
        guard let environment else { return }
        let allTracks: [AudioTrackRecord]
        do {
            allTracks = try environment.libraryDatabase.allTracks()
        } catch {
            AppLog.error(self, "createRandomPlaylist failed to fetch tracks error=\(error)")
            return
        }
        guard !allTracks.isEmpty else {
            AppLog.warning(self, "createRandomPlaylist no tracks in library")
            return
        }

        let count = min(count, allTracks.count)
        let selected = Array(allTracks.shuffled().prefix(count))

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        let name = "Random \(dateFormatter.string(from: Date()))"
        let playlist = store.createPlaylist(name: name)

        for track in selected {
            let entry = PlaylistEntry(
                trackID: track.trackID,
                title: track.title,
                artistName: track.artistName,
                albumID: track.albumID,
                albumTitle: track.albumTitle,
                durationMillis: track.durationSeconds > 0 ? Int((track.durationSeconds * 1000).rounded()) : nil,
                trackNumber: track.trackNumber,
            )
            _ = store.addSong(entry, to: playlist.id)
        }
        reloadPlaylists()
    }

    // MARK: - Table View

    private func configureTableView() {
        tableView.delegate = self
        tableView.register(PlaylistCell.self, forCellReuseIdentifier: PlaylistCell.cellReuseID)
        tableView.register(PlaylistSearchCell.self, forCellReuseIdentifier: PlaylistSearchCell.searchReuseID)
        tableView.accessibilityIdentifier = "playlist.list"
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 72
        tableView.separatorStyle = .none
        tableView.backgroundColor = .clear
        tableView.applySoftEdgeEffects()
        tableView.allowsSelectionDuringEditing = true
        tableView.allowsMultipleSelectionDuringEditing = true

        view.addSubview(tableView)
        tableView.snp.makeConstraints { $0.edges.equalToSuperview() }
    }

    private func configureDataSource() {
        dataSource = PlaylistDiffableDataSource(
            tableView: tableView,
        ) { [weak self] (tableView: UITableView, indexPath: IndexPath, item: PlaylistItem) -> UITableViewCell? in
            guard let self else { return UITableViewCell() }

            switch item {
            case let .playlist(id):
                let cell = tableView.dequeueReusableCell(withIdentifier: PlaylistCell.cellReuseID, for: indexPath) as! PlaylistCell
                guard let playlist = playlistsByID[id] else { return cell }
                cell.configure(
                    with: playlist,
                    subtitle: playlistSubtitle(for: playlist),
                    apiClient: environment?.apiClient,
                    artworkCache: environment?.playlistCoverArtworkCache,
                    paths: environment?.paths,
                )
                cell.accessibilityIdentifier = "playlist.item.\(indexPath.row)"
                return cell

            case let .searchResult(id):
                let cell = tableView.dequeueReusableCell(withIdentifier: PlaylistSearchCell.searchReuseID, for: indexPath) as! PlaylistSearchCell
                guard let result = searchResultsByID[id] else { return cell }
                cell.configure(
                    with: result.playlist,
                    query: currentQuery,
                    matchingSongNames: result.matchingSongNames,
                    fallbackSubtitle: playlistSubtitle(for: result.playlist),
                    apiClient: environment?.apiClient,
                    artworkCache: environment?.playlistCoverArtworkCache,
                    paths: environment?.paths,
                )
                return cell
            }
        }
        dataSource.defaultRowAnimation = .fade
        dataSource.isSearchActiveProvider = { [weak self] in self?.isSearchActive ?? false }
    }

    // MARK: - Empty State

    private func configureEmptyState() {
        view.addSubview(emptyStateView)
        emptyStateView.snp.makeConstraints { make in
            make.center.equalTo(view.safeAreaLayoutGuide)
        }
        view.addSubview(noResultsView)
        noResultsView.snp.makeConstraints { make in
            make.center.equalTo(view.safeAreaLayoutGuide)
        }
    }

    private func updateEmptyState() {
        if isSearchActive {
            emptyStateView.isHidden = true
            noResultsView.isHidden = !orderedSearchResultIDs.isEmpty
        } else {
            emptyStateView.isHidden = !store.playlists.isEmpty
            noResultsView.isHidden = true
        }
    }

    // MARK: - Data

    func rebuildPlaylistIndex() {
        playlistsByID = Dictionary(uniqueKeysWithValues: store.playlists.map { ($0.id, $0) })
    }

    func reloadPlaylists(animated: Bool = true) {
        store.reload()
        rebuildPlaylistIndex()
        applySort()
        if isSearchActive {
            scheduleSearch(query: currentQuery, debounce: false, animated: animated)
        } else {
            applyPlaylistsSnapshot(animated: animated)
        }
        updateNavigationItems()
    }

    private func prepareInitialDataIfNeeded() {
        guard !hasPreparedInitialData else {
            return
        }
        hasPreparedInitialData = true
        reloadPlaylists(animated: false)
    }

    func applySort() {
        sortedPlaylists = store.playlists
        switch sortOption {
        case .name:
            sortedPlaylists.sort {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        case .trackCount:
            sortedPlaylists.sort {
                if $0.songs.count != $1.songs.count {
                    return $0.songs.count > $1.songs.count
                }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        case .duration:
            sortedPlaylists.sort {
                let d0 = $0.songs.reduce(0) { $0 + ($1.durationMillis ?? 0) }
                let d1 = $1.songs.reduce(0) { $0 + ($1.durationMillis ?? 0) }
                if d0 != d1 {
                    return d0 > d1
                }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        case .recentlyModified:
            sortedPlaylists.sort {
                if $0.updatedAt != $1.updatedAt {
                    return $0.updatedAt > $1.updatedAt
                }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        case .recentlyCreated:
            sortedPlaylists.sort {
                if $0.createdAt != $1.createdAt {
                    return $0.createdAt > $1.createdAt
                }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }
    }

    // MARK: - Snapshots

    func applyPlaylistsSnapshot(animated: Bool) {
        let previousItems = Set(dataSource.snapshot().itemIdentifiers)
        var snapshot = NSDiffableDataSourceSnapshot<PlaylistSection, PlaylistItem>()
        snapshot.appendSections([PlaylistSection.playlists])
        let items: [PlaylistItem] = sortedPlaylists.map { PlaylistItem.playlist($0.id) }
        snapshot.appendItems(items, toSection: PlaylistSection.playlists)
        let itemsToReconfigure = items.filter { previousItems.contains($0) }
        if !itemsToReconfigure.isEmpty {
            snapshot.reconfigureItems(itemsToReconfigure)
        }
        let shouldAnimate = hasAppliedInitialSnapshot && animated
        dataSource.apply(snapshot, animatingDifferences: shouldAnimate)
        hasAppliedInitialSnapshot = true
        updateEmptyState()
    }

    func applySearchSnapshot(animated: Bool) {
        let previousItems = Set(dataSource.snapshot().itemIdentifiers)
        var snapshot = NSDiffableDataSourceSnapshot<PlaylistSection, PlaylistItem>()
        snapshot.appendSections([PlaylistSection.searchResults])
        let items: [PlaylistItem] = orderedSearchResultIDs.map { PlaylistItem.searchResult($0) }
        snapshot.appendItems(items, toSection: PlaylistSection.searchResults)
        let itemsToReconfigure = items.filter { previousItems.contains($0) }
        if !itemsToReconfigure.isEmpty {
            snapshot.reconfigureItems(itemsToReconfigure)
        }
        let shouldAnimate = hasAppliedInitialSnapshot && animated
        dataSource.apply(snapshot, animatingDifferences: shouldAnimate)
        hasAppliedInitialSnapshot = true
        updateEmptyState()
    }
}
