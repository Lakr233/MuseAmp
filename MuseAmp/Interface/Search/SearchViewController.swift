//
//  SearchViewController.swift
//  MuseAmp
//
//  Created by @Lakr233 on 2026/04/11.
//

import Combine
import ConfigurableKit
import Kingfisher
import MuseAmpDatabaseKit
import SnapKit
import Then
import UIKit

nonisolated enum SearchSection: Hashable {
    case songs
    case albums
    case artists
    case loading

    static let resultSections: [SearchSection] = [.songs, .albums, .artists]
}

nonisolated enum SearchItem: Hashable {
    case artist(String)
    case song(String)
    case album(String)
    case showMore(SearchSection)
    case loadingIndicator
}

@MainActor
class SearchViewController: UIViewController {
    typealias Section = SearchSection

    let environment: AppEnvironment
    let searchController = UISearchController(searchResultsController: nil)
    let tableView = UITableView(frame: .zero, style: .plain)
    let apiClient: APIClient

    let songPageSize = 10
    let mediaPageSize = 5

    var searchState = SearchResultsState()
    var searchTask: Task<Void, Never>?
    var debounceTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    lazy var playlistMenuProvider = AddToPlaylistMenuProvider(
        playlistStore: environment.playlistStore,
        viewController: self,
    )
    lazy var playbackMenuProvider = PlaybackMenuProvider(
        playbackController: environment.playbackController,
    )
    lazy var lyricsReloadPresenter = LyricsReloadPresenter(
        reloadService: environment.lyricsReloadService,
        viewController: self,
    )
    lazy var songContextMenuProvider = SongContextMenuProvider(
        playlistMenuProvider: playlistMenuProvider,
        lyricsReloadPresenter: lyricsReloadPresenter,
    )
    lazy var albumNavigationHelper = AlbumNavigationHelper(
        environment: environment,
        viewController: self,
    )
    lazy var artistNavigationHelper = ArtistNavigationHelper(
        environment: environment,
        viewController: self,
    )

    let historyStore = SearchHistoryStore()
    let historyTableView = UITableView(frame: .zero, style: .plain)
    var searchHistory: [String] = []

    lazy var diffableDataSource: UITableViewDiffableDataSource<SearchSection, SearchItem> = {
        let ds = UITableViewDiffableDataSource<SearchSection, SearchItem>(tableView: tableView) { [weak self] tableView, indexPath, item in
            guard let self else { return UITableViewCell() }
            return cell(for: tableView, at: indexPath, item: item)
        }
        ds.defaultRowAnimation = .fade
        return ds
    }()

    init(environment: AppEnvironment) {
        self.environment = environment
        apiClient = environment.apiClient
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "Search")
        view.backgroundColor = .systemBackground
        configureSearchController()
        configureTableView()
        configureHistoryTableView()
        loadHistory()

        ConfigurableKit.publisher(
            forKey: AppPreferences.cleanSongTitleKey, type: Bool.self,
        )
        .dropFirst()
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in self?.tableView.reloadData() }
        .store(in: &cancellables)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !searchController.isActive, searchController.searchBar.text?.isEmpty != false {
            searchController.searchBar.becomeFirstResponder()
        }
    }

    private func configureSearchController() {
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = String(localized: "Songs, Albums, Artists")
        searchController.searchBar.accessibilityIdentifier = "search.bar"
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true
    }

    private func configureTableView() {
        tableView.delegate = self
        tableView.register(AmSongCell.self, forCellReuseIdentifier: AmSongCell.reuseID)
        tableView.register(AmMediaCell.self, forCellReuseIdentifier: AmMediaCell.reuseID)
        tableView.register(ShowMoreCell.self, forCellReuseIdentifier: ShowMoreCell.reuseID)
        tableView.register(SearchLoadingCell.self, forCellReuseIdentifier: SearchLoadingCell.reuseID)
        tableView.register(SearchSectionHeaderView.self, forHeaderFooterViewReuseIdentifier: SearchSectionHeaderView.reuseID)
        tableView.accessibilityIdentifier = "search.results"
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 64
        tableView.separatorStyle = .none
        tableView.sectionHeaderTopPadding = 0
        view.addSubview(tableView)
        tableView.snp.makeConstraints { $0.edges.equalToSuperview() }
        tableView.dataSource = diffableDataSource
    }

    private func configureHistoryTableView() {
        historyTableView.delegate = self
        historyTableView.dataSource = self
        historyTableView.register(UITableViewCell.self, forCellReuseIdentifier: "HistoryCell")
        historyTableView.separatorStyle = .none
        historyTableView.sectionHeaderTopPadding = 0
        historyTableView.keyboardDismissMode = .onDrag
        historyTableView.register(SearchSectionHeaderView.self, forHeaderFooterViewReuseIdentifier: SearchSectionHeaderView.reuseID)
        historyTableView.clipsToBounds = true
        view.addSubview(historyTableView)
        historyTableView.snp.makeConstraints { $0.edges.equalTo(view.safeAreaLayoutGuide) }
    }

    private func cell(for tableView: UITableView, at indexPath: IndexPath, item: SearchItem) -> UITableViewCell {
        switch item {
        case let .artist(id):
            let cell = tableView.dequeueReusableCell(withIdentifier: AmMediaCell.reuseID, for: indexPath) as! AmMediaCell
            if let artist = searchState.artists.items.first(where: { $0.id == id }) {
                cell.configure(
                    content: MediaRowContent(
                        title: artist.attributes.name,
                        artwork: ArtworkContent(
                            placeholderIcon: "person.fill",
                            cornerRadius: 22,
                        ),
                    ),
                )
                cell.loadArtwork(url: apiClient.mediaURL(from: artist.attributes.artwork?.url, width: 88, height: 88))
                cell.setAttributedTitle(
                    SearchHighlightHelper.attributedString(
                        text: artist.attributes.name,
                        query: searchState.currentQuery,
                        font: .systemFont(ofSize: 16),
                        color: .label,
                    ),
                )
            }
            cell.accessibilityIdentifier = "search.result.artists.\(indexPath.row)"
            return cell
        case let .song(id):
            let cell = tableView.dequeueReusableCell(withIdentifier: AmSongCell.reuseID, for: indexPath) as! AmSongCell
            if let song = searchState.songs.items.first(where: { $0.id == id }) {
                let subtitle = [song.attributes.artistName, song.attributes.albumName]
                    .compactMap { value in
                        guard let value, !value.isEmpty else {
                            return nil
                        }
                        return value
                    }
                    .joined(separator: " · ")
                let title = song.attributes.name.sanitizedTrackTitle
                cell.configure(
                    content: SongRowContent(
                        title: title,
                        subtitle: subtitle.nilIfEmpty,
                        trailingText: song.attributes.durationInMillis.map { formattedDuration(millis: $0) },
                        artworkURL: apiClient.mediaURL(from: song.attributes.artwork?.url, width: 88, height: 88),
                    ),
                )
                cell.setAttributedTitle(
                    SearchHighlightHelper.attributedString(
                        text: title,
                        query: searchState.currentQuery,
                        font: .systemFont(ofSize: 16),
                        color: .label,
                    ),
                )
                cell.setAttributedSubtitle(
                    subtitle.nilIfEmpty.map {
                        SearchHighlightHelper.attributedString(
                            text: $0,
                            query: searchState.currentQuery,
                            font: .systemFont(ofSize: 13),
                            color: PlatformInterfacePalette.secondaryText,
                        )
                    },
                )
                cell.accessoryView = makeSongMenuButton(for: song)
            }
            cell.accessibilityIdentifier = "search.result.songs.\(indexPath.row)"
            return cell
        case let .album(id):
            let cell = tableView.dequeueReusableCell(withIdentifier: AmMediaCell.reuseID, for: indexPath) as! AmMediaCell
            if let album = searchState.albums.items.first(where: { $0.id == id }) {
                cell.configure(
                    content: MediaRowContent(
                        title: album.attributes.name,
                        subtitle: album.attributes.artistName,
                        artwork: ArtworkContent(
                            placeholderIcon: "square.stack.fill",
                            cornerRadius: 6,
                        ),
                    ),
                )
                cell.loadArtwork(url: apiClient.mediaURL(from: album.attributes.artwork?.url, width: 88, height: 88))
                cell.setAttributedTitle(
                    SearchHighlightHelper.attributedString(
                        text: album.attributes.name,
                        query: searchState.currentQuery,
                        font: .systemFont(ofSize: 16),
                        color: .label,
                    ),
                )
                cell.setAttributedSubtitle(
                    SearchHighlightHelper.attributedString(
                        text: album.attributes.artistName,
                        query: searchState.currentQuery,
                        font: .systemFont(ofSize: 14),
                        color: PlatformInterfacePalette.secondaryText,
                    ),
                )
            }
            cell.accessibilityIdentifier = "search.result.albums.\(indexPath.row)"
            return cell
        case let .showMore(section):
            let cell = tableView.dequeueReusableCell(withIdentifier: ShowMoreCell.reuseID, for: indexPath) as! ShowMoreCell
            cell.configure(isLoading: searchState.loadingMore.contains(section))
            return cell
        case .loadingIndicator:
            let cell = tableView.dequeueReusableCell(withIdentifier: SearchLoadingCell.reuseID, for: indexPath) as! SearchLoadingCell
            cell.startAnimating()
            return cell
        }
    }

    func applySnapshot(animating: Bool = true) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, SearchItem>()

        if searchState.isSearching {
            snapshot.appendSections([.loading])
            snapshot.appendItems([.loadingIndicator], toSection: .loading)
        } else {
            for section in searchState.sectionOrder {
                switch section {
                case .artists where !searchState.artists.items.isEmpty:
                    snapshot.appendSections([.artists])
                    snapshot.appendItems(searchState.artists.items.map { .artist($0.id) }, toSection: .artists)
                    if searchState.artists.hasMore { snapshot.appendItems([.showMore(.artists)], toSection: .artists) }
                case .albums where !searchState.albums.items.isEmpty:
                    snapshot.appendSections([.albums])
                    snapshot.appendItems(searchState.albums.items.map { .album($0.id) }, toSection: .albums)
                    if searchState.albums.hasMore { snapshot.appendItems([.showMore(.albums)], toSection: .albums) }
                case .songs where !searchState.songs.items.isEmpty:
                    snapshot.appendSections([.songs])
                    snapshot.appendItems(searchState.songs.items.map { .song($0.id) }, toSection: .songs)
                    if searchState.songs.hasMore { snapshot.appendItems([.showMore(.songs)], toSection: .songs) }
                case .loading:
                    break
                default: break
                }
            }
        }
        let showMoreItems = snapshot.itemIdentifiers.filter {
            if case .showMore = $0 { return true }; return false
        }
        if !showMoreItems.isEmpty {
            snapshot.reconfigureItems(showMoreItems)
        }
        diffableDataSource.apply(snapshot, animatingDifferences: animating)

        if let errorMessage = searchState.searchError, !searchState.hasResults {
            let container = UIView()
            let label = UILabel()
            label.text = errorMessage
            label.textColor = .secondaryLabel
            label.textAlignment = .center
            label.numberOfLines = 0
            label.font = .preferredFont(forTextStyle: .body)
            container.addSubview(label)
            label.snp.makeConstraints { make in
                make.centerY.equalToSuperview()
                make.leading.trailing.equalTo(container.safeAreaLayoutGuide).inset(16)
            }
            tableView.backgroundView = container
        } else {
            tableView.backgroundView = nil
        }
    }

    func makeSongMenuButton(for song: CatalogSong) -> UIButton {
        let button = UIButton(type: .system)
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: "ellipsis.circle")
        configuration.baseForegroundColor = .secondaryLabel
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
        button.configuration = configuration
        button.menu = buildSongMenu(for: song)
        button.showsMenuAsPrimaryAction = true
        button.accessibilityLabel = String(localized: "More Actions")
        button.frame = CGRect(x: 0, y: 0, width: 36, height: 36)
        return button
    }
}
