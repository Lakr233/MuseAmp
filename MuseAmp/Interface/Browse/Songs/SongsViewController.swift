//
//  SongsViewController.swift
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

nonisolated enum SongsSection: Hashable {
    case songs
    case searchResults
}

nonisolated enum SongsItem: Hashable {
    case song(String)
}

final class SongsViewController: UIViewController {
    enum SongSortOption: String, CaseIterable {
        case title
        case artist
        case album
        case recentlyModified
        case duration

        var title: String {
            switch self {
            case .title:
                String(localized: "Sort by Title")
            case .artist:
                String(localized: "Sort by Artist")
            case .album:
                String(localized: "Sort by Album")
            case .recentlyModified:
                String(localized: "Sort by Recently Modified")
            case .duration:
                String(localized: "Sort by Duration")
            }
        }

        var imageName: String {
            switch self {
            case .title:
                "textformat"
            case .artist:
                "person"
            case .album:
                "square.stack"
            case .recentlyModified:
                "clock"
            case .duration:
                "timer"
            }
        }
    }

    let environment: AppEnvironment
    let tableView = UITableView(frame: UIScreen.main.bounds, style: .plain)
    var dataSource: UITableViewDiffableDataSource<SongsSection, SongsItem>!
    var allTracks: [AudioTrackRecord] = []
    var tracksByID: [String: AudioTrackRecord] = [:]
    var filteredTracks: [AudioTrackRecord] = []
    var searchTracksByID: [String: AudioTrackRecord] = [:]
    var sortOption: SongSortOption = AppPreferences.storedSortOption(
        forKey: AppPreferences.songsSortOptionKey,
        defaultValue: .title,
    )
    var currentQuery = ""
    var searchTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []
    private var hasAppliedInitialSnapshot = false
    private var hasPreparedInitialData = false

    private let emptyStateView = EmptyStateView(
        icon: "music.note",
        title: String(localized: "No Songs Yet"),
        subtitle: String(localized: "Songs you save will appear here"),
    )

    private let noResultsView = EmptyStateView(
        icon: "magnifyingglass",
        title: String(localized: "No Results"),
        subtitle: String(localized: "Try a different search term"),
    ).then { $0.isHidden = true }

    lazy var searchController = UISearchController(searchResultsController: nil).then {
        $0.searchResultsUpdater = self
        $0.obscuresBackgroundDuringPresentation = false
        $0.searchBar.placeholder = String(localized: "Search Local Songs")
    }

    var isSearchActive: Bool {
        searchController.isActive && !(searchController.searchBar.text?.isEmpty ?? true)
    }

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
    lazy var lyricsReloadPresenter = LyricsReloadPresenter(
        reloadService: environment.lyricsReloadService,
        viewController: self,
    )
    lazy var songContextMenuProvider = SongContextMenuProvider(
        playlistMenuProvider: playlistMenuProvider,
        exportPresenter: songExportPresenter,
        lyricsReloadPresenter: lyricsReloadPresenter,
    )
    lazy var albumNavigationHelper = AlbumNavigationHelper(
        environment: environment,
        viewController: self,
    )

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

    init(environment: AppEnvironment) {
        self.environment = environment
        super.init(nibName: nil, bundle: nil)
        title = String(localized: "Songs")
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
            self, selector: #selector(handleLibraryDidSync),
            name: .libraryDidSync, object: nil,
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleArtworkDidUpdate(_:)),
            name: .artworkDidUpdate, object: nil,
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
        reloadTracks(animatingDifferences: false)
    }

    @objc private func handleLibraryDidSync() {
        reloadTracks()
    }

    @objc private func handleArtworkDidUpdate(_ notification: Notification) {
        guard let trackIDs = notification.userInfo?[AppNotificationUserInfoKey.trackIDs] as? [String] else {
            return
        }
        let affectedTrackIDs = Set(trackIDs)
        guard !affectedTrackIDs.isEmpty else { return }

        var snapshot = dataSource.snapshot()
        let itemsToReconfigure = snapshot.itemIdentifiers.filter { item in
            guard case let .song(trackID) = item else { return false }
            return affectedTrackIDs.contains(trackID)
        }
        guard !itemsToReconfigure.isEmpty else { return }
        snapshot.reconfigureItems(itemsToReconfigure)
        dataSource.apply(snapshot, animatingDifferences: hasAppliedInitialSnapshot && view.window != nil)
    }

    // MARK: - Data Loading

    func reloadTracks(animatingDifferences: Bool? = nil) {
        do {
            allTracks = try environment.libraryDatabase.allTracks()
        } catch {
            AppLog.error(self, "reloadTracks failed: \(error)")
            allTracks = []
        }
        applySort()
        tracksByID = Dictionary(uniqueKeysWithValues: allTracks.map { ($0.trackID, $0) })

        if isSearchActive {
            performSearch(query: currentQuery, animatingDifferences: animatingDifferences)
        } else {
            applySongsSnapshot(animatingDifferences: animatingDifferences)
        }
    }

    private func prepareInitialDataIfNeeded() {
        guard !hasPreparedInitialData else {
            return
        }
        hasPreparedInitialData = true
        reloadTracks(animatingDifferences: false)
    }

    // MARK: - Table View

    private func configureTableView() {
        tableView.delegate = self
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 64
        tableView.separatorStyle = .none
        tableView.allowsMultipleSelectionDuringEditing = true
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
        dataSource = UITableViewDiffableDataSource<SongsSection, SongsItem>(
            tableView: tableView,
        ) { [weak self] (tableView: UITableView, indexPath: IndexPath, item: SongsItem) -> UITableViewCell? in
            guard let self else { return UITableViewCell() }
            guard case let .song(trackID) = item else { return UITableViewCell() }

            let cell = tableView.dequeueReusableCell(withIdentifier: AmSongCell.reuseID, for: indexPath) as! AmSongCell

            let lookup = isSearchActive ? searchTracksByID : tracksByID
            guard let track = lookup[trackID] else { return cell }

            let cacheURL = environment.paths.artworkCacheURL(for: track.trackID)
            let artworkURL = FileManager.default.fileExists(atPath: cacheURL.path) ? cacheURL : nil
            cell.configure(content: SongRowContent(audioTrack: track, artworkURL: artworkURL))
            return cell
        }
        dataSource.defaultRowAnimation = .fade
    }

    private func configureNavBar() {
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true
        updateNavigationItems()
    }

    override func setEditing(_ editing: Bool, animated: Bool) {
        super.setEditing(editing, animated: animated)
        tableView.setEditing(editing, animated: animated)
        updateNavigationItems()
    }

    func updateNavigationItems() {
        if isEditing {
            navigationItem.leftBarButtonItem = finishSelectionButton
            navigationItem.rightBarButtonItems = [
                UIBarButtonItem(
                    image: UIImage(systemName: "ellipsis.circle"),
                    menu: buildEditingMenu(),
                ),
            ]
        } else {
            navigationItem.leftBarButtonItem = nil
            navigationItem.rightBarButtonItems = [
                UIBarButtonItem(
                    image: UIImage(systemName: "ellipsis.circle"),
                    menu: buildSongsMenu(),
                ),
                importButton,
            ]
        }
    }

    // MARK: - Snapshots

    func applySongsSnapshot(animatingDifferences: Bool? = nil) {
        var snapshot = NSDiffableDataSourceSnapshot<SongsSection, SongsItem>()
        snapshot.appendSections([.songs])
        snapshot.appendItems(allTracks.map { SongsItem.song($0.trackID) }, toSection: .songs)
        let animate = animatingDifferences ?? (hasAppliedInitialSnapshot && view.window != nil)
        dataSource.apply(snapshot, animatingDifferences: animate)
        hasAppliedInitialSnapshot = true
        updateEmptyState()
    }

    func applySearchSnapshot(animatingDifferences: Bool? = nil) {
        var snapshot = NSDiffableDataSourceSnapshot<SongsSection, SongsItem>()
        snapshot.appendSections([.searchResults])
        snapshot.appendItems(filteredTracks.map { SongsItem.song($0.trackID) }, toSection: .searchResults)
        let animate = animatingDifferences ?? (hasAppliedInitialSnapshot && view.window != nil)
        dataSource.apply(snapshot, animatingDifferences: animate)
        hasAppliedInitialSnapshot = true
        updateEmptyState()
    }

    private func updateEmptyState() {
        if isSearchActive {
            emptyStateView.isHidden = true
            noResultsView.isHidden = !filteredTracks.isEmpty
        } else {
            emptyStateView.isHidden = !allTracks.isEmpty
            noResultsView.isHidden = true
        }
    }

    // MARK: - Sorting

    func applySort() {
        switch sortOption {
        case .title:
            allTracks.sort {
                let titleOrder = $0.title.localizedCaseInsensitiveCompare($1.title)
                if titleOrder != .orderedSame {
                    return titleOrder == .orderedAscending
                }
                return $0.artistName.localizedCaseInsensitiveCompare($1.artistName) == .orderedAscending
            }
        case .artist:
            allTracks.sort {
                let artistOrder = $0.artistName.localizedCaseInsensitiveCompare($1.artistName)
                if artistOrder != .orderedSame {
                    return artistOrder == .orderedAscending
                }
                let albumOrder = $0.albumTitle.localizedCaseInsensitiveCompare($1.albumTitle)
                if albumOrder != .orderedSame {
                    return albumOrder == .orderedAscending
                }
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        case .album:
            allTracks.sort {
                let albumOrder = $0.albumTitle.localizedCaseInsensitiveCompare($1.albumTitle)
                if albumOrder != .orderedSame {
                    return albumOrder == .orderedAscending
                }
                let num0 = $0.trackNumber ?? Int.max
                let num1 = $1.trackNumber ?? Int.max
                if num0 != num1 {
                    return num0 < num1
                }
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        case .recentlyModified:
            allTracks.sort { $0.fileModifiedAt > $1.fileModifiedAt }
        case .duration:
            allTracks.sort {
                if $0.durationSeconds != $1.durationSeconds {
                    return $0.durationSeconds > $1.durationSeconds
                }
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        }
    }

    func sortTracks(by option: SongSortOption) {
        sortOption = option
        AppPreferences.setStoredSortOption(option, forKey: AppPreferences.songsSortOptionKey)
        applySort()
        applySongsSnapshot()
        updateNavigationItems()
    }

    // MARK: - Menu

    func buildSongsMenu() -> UIMenu {
        var sections: [UIMenuElement] = []

        let playbackActions = playbackMenuProvider.listPrimaryActions(
            tracksProvider: { [weak self] in self?.visiblePlaybackTracks() ?? [] },
            sourceProvider: { .library },
        )
        if let playbackSection = MenuSectionProvider.inline(playbackActions) {
            sections.append(playbackSection)
        }

        sections.append(buildSortMenu())

        let select = UIAction(
            title: String(localized: "Select"),
            image: UIImage(systemName: "checkmark.circle"),
        ) { [weak self] _ in
            self?.selectTapped()
        }
        if let manageSection = MenuSectionProvider.inline([select]) {
            sections.append(manageSection)
        }

        return UIMenu(children: sections)
    }

    func buildSortMenu() -> UIMenu {
        let actions = SongSortOption.allCases.map { option in
            UIAction(
                title: option.title,
                image: UIImage(systemName: option.imageName),
                state: option == sortOption ? .on : .off,
            ) { [weak self] _ in
                self?.sortTracks(by: option)
            }
        }
        return UIMenu(
            title: String(localized: "Sort By"),
            image: UIImage(systemName: "arrow.up.arrow.down"),
            options: .displayInline,
            children: actions,
        )
    }

    // MARK: - Helpers

    func visiblePlaybackTracks() -> [PlaybackTrack] {
        let tracks = isSearchActive ? filteredTracks : allTracks
        return tracks.map { $0.playbackTrack(paths: environment.paths) }
    }

    func playlistEntryForTrack(_ track: AudioTrackRecord) -> PlaylistEntry {
        track.playbackTrack(paths: environment.paths).playlistEntry
    }

    func exportItem(for track: AudioTrackRecord) -> SongExportItem {
        track.exportItem(paths: environment.paths)
    }
}

// MARK: - Import

extension SongsViewController: UIDocumentPickerDelegate {
    @objc func importTapped() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.audio, .folder])
        picker.allowsMultipleSelection = true
        picker.delegate = self
        present(picker, animated: true)
    }

    func documentPicker(_: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard !urls.isEmpty else { return }
        performImport(urls: urls)
    }

    func performImport(urls: [URL]) {
        let alert = AlertProgressIndicatorViewController(
            title: String(localized: "Importing"),
            message: String(localized: "Reading audio files..."),
        )
        present(alert, animated: true)

        Task { [weak self, importer = environment.audioFileImporter] in
            let result = await importer.importFiles(urls: urls) { current, total in
                alert.progressContext.purpose(
                    message: String(localized: "Importing \(current) / \(total)..."),
                )
            }

            await MainActor.run { [weak self] in
                alert.dismiss(animated: true) {
                    self?.showImportResult(result)
                }
            }
        }
    }

    private func showImportResult(_ result: AudioImportResult) {
        var lines: [String] = []
        if result.succeeded > 0 {
            lines.append(String(localized: "\(result.succeeded) song(s) imported."))
        }
        if result.duplicates > 0 {
            lines.append(String(localized: "\(result.duplicates) duplicate(s) skipped."))
        }
        if result.noMetadata > 0 {
            lines.append(String(localized: "\(result.noMetadata) file(s) had no metadata."))
        }
        if result.errors > 0 {
            lines.append(String(localized: "\(result.errors) file(s) failed."))
        }

        let alert = AlertViewController(
            title: String(localized: "Import Complete"),
            message: lines.joined(separator: "\n"),
        ) { context in
            context.addAction(title: String(localized: "OK"), attribute: .accent) {
                context.dispose()
            }
        }
        present(alert, animated: true)
    }
}
