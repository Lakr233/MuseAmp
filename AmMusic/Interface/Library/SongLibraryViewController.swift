import AlertController
import AmMusicDatabaseKit
import SnapKit
import Then
import UIKit
import UniformTypeIdentifiers

nonisolated enum LibrarySection: Hashable {
    case albums
    case searchResults
}

nonisolated enum LibraryItem: Hashable {
    case album(String)
    case track(String)
}

final class SongLibraryViewController: UIViewController {
    enum SortOption: CaseIterable {
        case album
        case artist
        case recentlyModified
        case trackCount
        case duration

        var title: String {
            switch self {
            case .album:
                String(localized: "Sort by Album")
            case .artist:
                String(localized: "Sort by Artist")
            case .recentlyModified:
                String(localized: "Sort by Recently Modified")
            case .trackCount:
                String(localized: "Sort by Track Count")
            case .duration:
                String(localized: "Sort by Duration")
            }
        }

        var imageName: String {
            switch self {
            case .album:
                "rectangle.stack"
            case .artist:
                "person"
            case .recentlyModified:
                "clock"
            case .trackCount:
                "number"
            case .duration:
                "timer"
            }
        }
    }

    let environment: AppEnvironment
    let tableView = UITableView(frame: .zero, style: .plain)
    var dataSource: UITableViewDiffableDataSource<LibrarySection, LibraryItem>!
    var albums: [AlbumGroup] = []
    var albumsByID: [String: AlbumGroup] = [:]
    var filteredTracks: [AudioTrackRecord] = []
    var tracksByID: [String: AudioTrackRecord] = [:]
    var sortOption: SortOption = .album
    var currentQuery = ""
    var searchTask: Task<Void, Never>?
    private var hasAppliedInitialSnapshot = false

    private let emptyStateView = EmptyStateView(
        icon: "square.stack.fill",
        title: String(localized: "No Albums Yet"),
        subtitle: String(localized: "Albums you save will appear here")
    )

    private let noResultsView = EmptyStateView(
        icon: "magnifyingglass",
        title: String(localized: "No Results"),
        subtitle: String(localized: "Try a different search term")
    ).then { $0.isHidden = true }

    lazy var searchController = UISearchController(searchResultsController: nil).then {
        $0.searchResultsUpdater = self
        $0.obscuresBackgroundDuringPresentation = false
        $0.searchBar.placeholder = String(localized: "Songs")
    }

    var isSearchActive: Bool {
        searchController.isActive && !(searchController.searchBar.text?.isEmpty ?? true)
    }

    lazy var finishSelectionButton = UIBarButtonItem(
        image: UIImage(systemName: "checkmark.circle"),
        style: .plain,
        target: self,
        action: #selector(finishSelectionTapped)
    )

    lazy var importButton = UIBarButtonItem(
        image: UIImage(systemName: "plus"),
        style: .plain,
        target: self,
        action: #selector(importTapped)
    )

    lazy var playbackMenuProvider = PlaybackMenuProvider(
        playbackController: environment.playbackController
    )
    lazy var songExportPresenter = SongExportPresenter(
        viewController: self,
        lyricsStore: environment.lyricsCacheStore,
        locations: environment.paths,
        apiClient: environment.apiClient
    )
    lazy var albumNavigationHelper = AlbumNavigationHelper(
        environment: environment,
        viewController: self
    )

    init(environment: AppEnvironment) {
        self.environment = environment
        super.init(nibName: nil, bundle: nil)
        title = String(localized: "Library")
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    deinit {
        NotificationCenter.default.removeObserver(self, name: .libraryDidSync, object: nil)
        NotificationCenter.default.removeObserver(self, name: .artworkDidUpdate, object: nil)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        configureTableView()
        configureDataSource()
        configureNavBar()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLibraryDidSync),
            name: .libraryDidSync,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleArtworkDidUpdate(_:)),
            name: .artworkDidUpdate,
            object: nil
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadAlbums()
    }

    @objc private func handleLibraryDidSync() {
        reloadAlbums()
    }

    @objc private func handleArtworkDidUpdate(_ notification: Notification) {
        guard let trackIDs = notification.userInfo?[AppNotificationUserInfoKey.trackIDs] as? [String] else {
            return
        }

        let affectedTrackIDs = Set(trackIDs)
        guard !affectedTrackIDs.isEmpty else {
            return
        }

        var snapshot = dataSource.snapshot()
        let itemsToReconfigure = snapshot.itemIdentifiers.filter { item in
            switch item {
            case let .album(albumID):
                guard let album = albumsByID[albumID],
                      let artworkTrackID = album.artworkTrackID
                else {
                    return false
                }
                return affectedTrackIDs.contains(artworkTrackID)
            case let .track(trackID):
                return affectedTrackIDs.contains(trackID)
            }
        }

        guard !itemsToReconfigure.isEmpty else {
            return
        }

        snapshot.reconfigureItems(itemsToReconfigure)
        dataSource.apply(snapshot, animatingDifferences: view.window != nil)
    }

    func reloadAlbums() {
        do {
            albums = try environment.libraryDatabase.allAlbums()
        } catch {
            AppLog.error(self, "reloadAlbums failed: \(error)")
            albums = []
        }
        applySort()
        albumsByID = Dictionary(uniqueKeysWithValues: albums.map { ($0.id, $0) })

        if isSearchActive {
            performSearch(query: currentQuery)
        } else {
            applyAlbumsSnapshot()
        }
    }

    private func configureTableView() {
        tableView.delegate = self
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 76
        tableView.separatorStyle = .none
        tableView.allowsMultipleSelectionDuringEditing = true
        tableView.register(AmMediaCell.self, forCellReuseIdentifier: AmMediaCell.reuseID)
        tableView.register(LibrarySearchResultCell.self, forCellReuseIdentifier: LibrarySearchResultCell.reuseID)
        view.addSubview(tableView)
        tableView.snp.makeConstraints { $0.edges.equalToSuperview() }

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

    private func configureDataSource() {
        dataSource = UITableViewDiffableDataSource<LibrarySection, LibraryItem>(
            tableView: tableView
        ) { [weak self] (tableView: UITableView, indexPath: IndexPath, item: LibraryItem) -> UITableViewCell? in
            guard let self else { return UITableViewCell() }
            switch item {
            case let .album(albumID):
                let cell = tableView.dequeueReusableCell(withIdentifier: AmMediaCell.reuseID, for: indexPath) as! AmMediaCell
                guard let album = albumsByID[albumID] else { return cell }
                let artworkTrackID = album.artworkTrackID ?? album.albumID
                let cacheURL = environment.paths.artworkCacheURL(for: artworkTrackID)
                cell.configure(
                    title: album.albumTitle,
                    subtitle: albumSubtitle(for: album),
                    artworkURL: FileManager.default.fileExists(atPath: cacheURL.path) ? cacheURL : nil,
                    placeholderIcon: "square.stack.fill",
                    roundArtwork: false
                )
                return cell

            case let .track(trackID):
                let cell = tableView.dequeueReusableCell(withIdentifier: LibrarySearchResultCell.reuseID, for: indexPath) as! LibrarySearchResultCell
                guard let track = tracksByID[trackID] else { return cell }
                let cacheURL = environment.paths.artworkCacheURL(for: track.trackID)
                let artworkURL = FileManager.default.fileExists(atPath: cacheURL.path) ? cacheURL : nil
                cell.configure(with: track, query: currentQuery, artworkURL: artworkURL)
                return cell
            }
        }
        dataSource.defaultRowAnimation = .fade
    }

    private func configureNavBar() {
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true
        updateNavigationItems()
    }

    func applyAlbumsSnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<LibrarySection, LibraryItem>()
        snapshot.appendSections([LibrarySection.albums])
        snapshot.appendItems(albums.map { LibraryItem.album($0.id) }, toSection: LibrarySection.albums)
        let animate = hasAppliedInitialSnapshot && view.window != nil
        dataSource.apply(snapshot, animatingDifferences: animate)
        hasAppliedInitialSnapshot = true
        updateEmptyState()
    }

    func applySearchSnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<LibrarySection, LibraryItem>()
        snapshot.appendSections([LibrarySection.searchResults])
        snapshot.appendItems(filteredTracks.map { LibraryItem.track($0.trackID) }, toSection: LibrarySection.searchResults)
        dataSource.apply(snapshot, animatingDifferences: view.window != nil)
        updateEmptyState()
    }

    private func updateEmptyState() {
        if isSearchActive {
            emptyStateView.isHidden = true
            noResultsView.isHidden = !filteredTracks.isEmpty
        } else {
            emptyStateView.isHidden = !albums.isEmpty
            noResultsView.isHidden = true
        }
    }

    func applySort() {
        switch sortOption {
        case .album:
            albums.sort {
                let titleOrder = $0.albumTitle.localizedCaseInsensitiveCompare($1.albumTitle)
                if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
                return $0.artistName.localizedCaseInsensitiveCompare($1.artistName) == .orderedAscending
            }
        case .artist:
            albums.sort {
                let artistOrder = $0.artistName.localizedCaseInsensitiveCompare($1.artistName)
                if artistOrder != .orderedSame { return artistOrder == .orderedAscending }
                return $0.albumTitle.localizedCaseInsensitiveCompare($1.albumTitle) == .orderedAscending
            }
        case .recentlyModified:
            albums.sort {
                $0.albumTitle.localizedCaseInsensitiveCompare($1.albumTitle) == .orderedAscending
            }
        case .trackCount:
            albums.sort {
                if $0.trackCount != $1.trackCount { return $0.trackCount > $1.trackCount }
                return $0.albumTitle.localizedCaseInsensitiveCompare($1.albumTitle) == .orderedAscending
            }
        case .duration:
            albums.sort {
                if $0.totalDurationSeconds != $1.totalDurationSeconds { return $0.totalDurationSeconds > $1.totalDurationSeconds }
                return $0.albumTitle.localizedCaseInsensitiveCompare($1.albumTitle) == .orderedAscending
            }
        }
    }
}
