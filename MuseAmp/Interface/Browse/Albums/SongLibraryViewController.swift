//
//  SongLibraryViewController.swift
//  MuseAmp
//
//  Created by @Lakr233 on 2026/04/11.
//

import AlertController
import Combine
import ConfigurableKit
import MuseAmpDatabaseKit
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
    enum SortOption: String, CaseIterable {
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
    let tableView = UITableView(frame: UIScreen.main.bounds, style: .plain)
    var dataSource: UITableViewDiffableDataSource<LibrarySection, LibraryItem>!
    var albums: [AlbumGroup] = []
    var albumsByID: [String: AlbumGroup] = [:]
    var filteredTracks: [AudioTrackRecord] = []
    var tracksByID: [String: AudioTrackRecord] = [:]
    var sortOption: SortOption = AppPreferences.storedSortOption(
        forKey: AppPreferences.libraryAlbumSortOptionKey,
        defaultValue: .album,
    )
    var currentQuery = ""
    var searchTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []
    private var hasAppliedInitialSnapshot = false
    private var hasPreparedInitialData = false

    private let emptyStateView = EmptyStateView(
        icon: "square.stack.fill",
        title: String(localized: "No Albums Yet"),
        subtitle: String(localized: "Albums you save will appear here"),
    )

    private let noResultsView = EmptyStateView(
        icon: "magnifyingglass",
        title: String(localized: "No Results"),
        subtitle: String(localized: "Try a different search term"),
    ).then { $0.isHidden = true }

    lazy var searchController = UISearchController(searchResultsController: nil).then {
        $0.searchResultsUpdater = self
        $0.obscuresBackgroundDuringPresentation = false
        $0.searchBar.placeholder = String(localized: "Search Local Library")
    }

    var isSearchActive: Bool {
        searchController.isActive && !(searchController.searchBar.text?.isEmpty ?? true)
    }

    lazy var finishSelectionButton = UIBarButtonItem(
        image: UIImage(systemName: "checkmark.circle"),
        style: .plain,
        target: self,
        action: #selector(finishSelectionTapped),
    )

    lazy var importButton = UIBarButtonItem(
        image: UIImage(systemName: "plus"),
        style: .plain,
        target: self,
        action: #selector(importTapped),
    )

    lazy var playbackMenuProvider = PlaybackMenuProvider(
        playbackController: environment.playbackController,
    )
    lazy var playlistMenuProvider = AddToPlaylistMenuProvider(
        playlistStore: environment.playlistStore,
        viewController: self,
    )
    lazy var songExportPresenter = SongExportPresenter(
        viewController: self,
        lyricsStore: environment.lyricsCacheStore,
        locations: environment.paths,
        apiClient: environment.apiClient,
        trackRemovalService: environment.musicLibraryTrackRemovalService,
    )
    lazy var albumNavigationHelper = AlbumNavigationHelper(
        environment: environment,
        viewController: self,
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
            object: nil,
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleArtworkDidUpdate(_:)),
            name: .artworkDidUpdate,
            object: nil,
        )

        ConfigurableKit.publisher(
            forKey: AppPreferences.cleanSongTitleKey, type: Bool.self,
        )
        .dropFirst()
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in self?.tableView.reloadData() }
        .store(in: &cancellables)

        prepareInitialDataIfNeeded()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard hasPreparedInitialData else {
            return
        }
        reloadAlbums(animatingDifferences: false)
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
        dataSource.apply(snapshot, animatingDifferences: hasAppliedInitialSnapshot && view.window != nil)
    }

    func reloadAlbums(animatingDifferences: Bool? = nil) {
        do {
            albums = try environment.libraryDatabase.allAlbums()
        } catch {
            AppLog.error(self, "reloadAlbums failed: \(error)")
            albums = []
        }
        applySort()
        albumsByID = Dictionary(uniqueKeysWithValues: albums.map { ($0.id, $0) })

        if isSearchActive {
            performSearch(query: currentQuery, animatingDifferences: animatingDifferences)
        } else {
            applyAlbumsSnapshot(animatingDifferences: animatingDifferences)
        }
    }

    private func prepareInitialDataIfNeeded() {
        guard !hasPreparedInitialData else {
            return
        }
        hasPreparedInitialData = true
        reloadAlbums(animatingDifferences: false)
    }

    private func configureTableView() {
        tableView.delegate = self
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 76
        tableView.separatorStyle = .none
        tableView.allowsMultipleSelectionDuringEditing = true
        tableView.register(AmMediaCell.self, forCellReuseIdentifier: AmMediaCell.reuseID)
        tableView.register(AmSongCell.self, forCellReuseIdentifier: AmSongCell.reuseID)
        view.addSubview(tableView)
        tableView.snp.makeConstraints { $0.edges.equalToSuperview() }

        view.addSubview(emptyStateView)
        emptyStateView.snp.makeConstraints { make in
            make.center.equalTo(view.safeAreaLayoutGuide)
        }

        view.addSubview(noResultsView)
        noResultsView.snp.makeConstraints { make in
            make.center.equalTo(view.safeAreaLayoutGuide)
        }
    }

    private func configureDataSource() {
        dataSource = UITableViewDiffableDataSource<LibrarySection, LibraryItem>(
            tableView: tableView,
        ) { [weak self] (tableView: UITableView, indexPath: IndexPath, item: LibraryItem) -> UITableViewCell? in
            guard let self else { return UITableViewCell() }
            switch item {
            case let .album(albumID):
                let cell = tableView.dequeueReusableCell(withIdentifier: AmMediaCell.reuseID, for: indexPath) as! AmMediaCell
                guard let album = albumsByID[albumID] else { return cell }
                let artworkTrackID = album.artworkTrackID ?? album.albumID
                let cacheURL = environment.paths.artworkCacheURL(for: artworkTrackID)
                cell.configure(
                    content: MediaRowContent(
                        title: album.albumTitle,
                        subtitle: albumSubtitle(for: album),
                        artwork: ArtworkContent(
                            placeholderIcon: "square.stack.fill",
                            cornerRadius: 6,
                        ),
                    ),
                )
                cell.loadArtwork(url: FileManager.default.fileExists(atPath: cacheURL.path) ? cacheURL : nil)
                return cell

            case let .track(trackID):
                let cell = tableView.dequeueReusableCell(withIdentifier: AmSongCell.reuseID, for: indexPath) as! AmSongCell
                guard let track = tracksByID[trackID] else { return cell }
                let cacheURL = environment.paths.artworkCacheURL(for: track.trackID)
                let artworkURL = FileManager.default.fileExists(atPath: cacheURL.path) ? cacheURL : nil
                configureLibrarySearchResultCell(
                    cell,
                    with: track,
                    query: currentQuery,
                    artworkURL: artworkURL,
                )
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

    func applyAlbumsSnapshot(animatingDifferences: Bool? = nil) {
        var snapshot = NSDiffableDataSourceSnapshot<LibrarySection, LibraryItem>()
        snapshot.appendSections([LibrarySection.albums])
        snapshot.appendItems(albums.map { LibraryItem.album($0.id) }, toSection: LibrarySection.albums)
        let animate = animatingDifferences ?? (hasAppliedInitialSnapshot && view.window != nil)
        dataSource.apply(snapshot, animatingDifferences: animate)
        hasAppliedInitialSnapshot = true
        updateEmptyState()
    }

    func applySearchSnapshot(animatingDifferences: Bool? = nil) {
        var snapshot = NSDiffableDataSourceSnapshot<LibrarySection, LibraryItem>()
        snapshot.appendSections([LibrarySection.searchResults])
        snapshot.appendItems(filteredTracks.map { LibraryItem.track($0.trackID) }, toSection: LibrarySection.searchResults)
        let animate = animatingDifferences ?? (hasAppliedInitialSnapshot && view.window != nil)
        dataSource.apply(snapshot, animatingDifferences: animate)
        hasAppliedInitialSnapshot = true
        updateEmptyState()
    }

    func configureLibrarySearchResultCell(
        _ cell: AmSongCell,
        with track: AudioTrackRecord,
        query: String,
        artworkURL: URL?,
    ) {
        cell.configure(content: SongRowContent(audioTrack: track, artworkURL: artworkURL))

        let subtitle = [track.artistName, track.albumTitle]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")

        cell.setAttributedTitle(SearchHighlightHelper.attributedString(
            text: track.title.sanitizedTrackTitle,
            query: query,
            font: .systemFont(ofSize: 16),
            color: .label,
        ))
        cell.setAttributedSubtitle(SearchHighlightHelper.attributedString(
            text: subtitle,
            query: query,
            font: .systemFont(ofSize: 13),
            color: .secondaryLabel,
        ))
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
                if titleOrder != .orderedSame {
                    return titleOrder == .orderedAscending
                }
                return $0.artistName.localizedCaseInsensitiveCompare($1.artistName) == .orderedAscending
            }
        case .artist:
            albums.sort {
                let artistOrder = $0.artistName.localizedCaseInsensitiveCompare($1.artistName)
                if artistOrder != .orderedSame {
                    return artistOrder == .orderedAscending
                }
                return $0.albumTitle.localizedCaseInsensitiveCompare($1.albumTitle) == .orderedAscending
            }
        case .recentlyModified:
            albums.sort {
                let lhs = $0.latestModifiedAt ?? .distantPast
                let rhs = $1.latestModifiedAt ?? .distantPast
                if lhs != rhs {
                    return lhs > rhs
                }
                return $0.albumTitle.localizedCaseInsensitiveCompare($1.albumTitle) == .orderedAscending
            }
        case .trackCount:
            albums.sort {
                if $0.trackCount != $1.trackCount {
                    return $0.trackCount > $1.trackCount
                }
                return $0.albumTitle.localizedCaseInsensitiveCompare($1.albumTitle) == .orderedAscending
            }
        case .duration:
            albums.sort {
                if $0.totalDurationSeconds != $1.totalDurationSeconds {
                    return $0.totalDurationSeconds > $1.totalDurationSeconds
                }
                return $0.albumTitle.localizedCaseInsensitiveCompare($1.albumTitle) == .orderedAscending
            }
        }
    }
}
