import AlertController
import AmMusicDatabaseKit
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
        if case PlaylistItem.playlist = item { return true }
        return false
    }
}

class PlaylistViewController: UIViewController {
    enum SortOption: CaseIterable {
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
    let tableView = UITableView(frame: .zero, style: .plain)
    var sortOption: SortOption = .recentlyModified
    var sortedPlaylists: [Playlist] = []
    private var playlistsDidChangeObserver: NSObjectProtocol?
    lazy var playlistMenuProvider = PlaylistContextMenuProvider(
        playlistStore: store,
        viewController: self
    )
    lazy var addButton = UIBarButtonItem(
        image: UIImage(systemName: "plus"),
        style: .plain,
        target: self,
        action: #selector(addTapped)
    ).then {
        $0.accessibilityIdentifier = "playlist.add"
    }

    lazy var finishSelectionButton = UIBarButtonItem(
        image: UIImage(systemName: "checkmark.circle"),
        style: .plain,
        target: self,
        action: #selector(finishSelectionTapped)
    )

    var dataSource: PlaylistDiffableDataSource!
    var playlistsByID: [UUID: Playlist] = [:]
    var searchResultsByID: [UUID: (playlist: Playlist, matchingSongNames: [String])] = [:]
    var orderedSearchResultIDs: [UUID] = []

    // MARK: - Search

    var currentQuery = ""
    var searchTask: Task<Void, Never>?

    var isSearchActive: Bool {
        searchController.isActive && !(searchController.searchBar.text?.isEmpty ?? true)
    }

    lazy var searchController = UISearchController(searchResultsController: nil).then {
        $0.searchResultsUpdater = self
        $0.obscuresBackgroundDuringPresentation = false
        $0.searchBar.placeholder = String(localized: "Playlists, Songs")
    }

    // MARK: - Empty States

    private let emptyStateView = EmptyStateView(
        icon: "music.note.list",
        title: String(localized: "No Playlists Yet"),
        subtitle: String(localized: "Tap + to create your first playlist")
    )

    private let noResultsView = EmptyStateView(
        icon: "magnifyingglass",
        title: String(localized: "No Results"),
        subtitle: String(localized: "Try a different search term")
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
        title = String(localized: "Playlist")
        navigationController?.navigationBar.prefersLargeTitles = true
        view.backgroundColor = .systemBackground

        configureTableView()
        configureDataSource()
        configureNavBar()
        configureEmptyState()
        observePlaylistChanges()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        store.reload()
        rebuildPlaylistIndex()
        applySort()
        applyPlaylistsSnapshot(animated: false)
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
            queue: .main
        ) { [weak self] _ in
            self?.reloadPlaylists()
        }
    }

    @objc private func addTapped() {
        let alert = AlertInputViewController(
            title: String(localized: "New Playlist"),
            message: String(localized: "Enter a name for your playlist."),
            placeholder: String(localized: "Playlist Name"),
            text: ""
        ) { [weak self] name in
            guard let self else { return }
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                AppLog.warning(self, "addTapped empty name after trim, ignoring")
                return
            }
            store.createPlaylist(name: trimmed)
            reloadPlaylists()
        }
        present(alert, animated: true)
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
        tableView.allowsMultipleSelectionDuringEditing = true

        view.addSubview(tableView)
        tableView.snp.makeConstraints { $0.edges.equalToSuperview() }
    }

    private func configureDataSource() {
        dataSource = PlaylistDiffableDataSource(
            tableView: tableView
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
                    artworkCache: environment?.playlistCoverArtworkCache
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
                    artworkCache: environment?.playlistCoverArtworkCache
                )
                return cell
            }
        }
        dataSource.defaultRowAnimation = .fade
        dataSource.isSearchActiveProvider = { [weak self] in self?.isSearchActive ?? false }
    }

    // MARK: - Empty State

    private func configureEmptyState() {
        tableView.addSubview(emptyStateView)
        emptyStateView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalToSuperview().offset(200)
        }
        tableView.addSubview(noResultsView)
        noResultsView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalToSuperview().offset(200)
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

    func reloadPlaylists() {
        store.reload()
        rebuildPlaylistIndex()
        applySort()
        if isSearchActive {
            scheduleSearch(query: currentQuery, debounce: false)
        } else {
            applyPlaylistsSnapshot(animated: true)
        }
        updateNavigationItems()
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
                if $0.songs.count != $1.songs.count { return $0.songs.count > $1.songs.count }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        case .duration:
            sortedPlaylists.sort {
                let d0 = $0.songs.reduce(0) { $0 + ($1.durationMillis ?? 0) }
                let d1 = $1.songs.reduce(0) { $0 + ($1.durationMillis ?? 0) }
                if d0 != d1 { return d0 > d1 }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        case .recentlyModified:
            sortedPlaylists.sort {
                if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        case .recentlyCreated:
            sortedPlaylists.sort {
                if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }
    }

    // MARK: - Snapshots

    func applyPlaylistsSnapshot(animated: Bool) {
        var snapshot = NSDiffableDataSourceSnapshot<PlaylistSection, PlaylistItem>()
        snapshot.appendSections([PlaylistSection.playlists])
        let items: [PlaylistItem] = sortedPlaylists.map { PlaylistItem.playlist($0.id) }
        snapshot.appendItems(items, toSection: PlaylistSection.playlists)
        dataSource.apply(snapshot, animatingDifferences: animated)
        updateEmptyState()
    }

    func applySearchSnapshot(animated: Bool) {
        var snapshot = NSDiffableDataSourceSnapshot<PlaylistSection, PlaylistItem>()
        snapshot.appendSections([PlaylistSection.searchResults])
        let items: [PlaylistItem] = orderedSearchResultIDs.map { PlaylistItem.searchResult($0) }
        snapshot.appendItems(items, toSection: PlaylistSection.searchResults)
        dataSource.apply(snapshot, animatingDifferences: animated)
        updateEmptyState()
    }
}
