import AlertController
import AmMusicDatabaseKit
import SnapKit
import Then
import UIKit

nonisolated enum AlbumSection: Int, Hashable {
    case tracks
}

nonisolated enum AlbumItem: Hashable {
    case skeleton(index: Int)
    case track(position: Int, id: String, number: Int)
}

@MainActor
class AlbumDetailViewController: MediaDetailViewController {
    var album: CatalogAlbum
    let environment: AppEnvironment
    let apiClient: APIClient
    var tracks: [CatalogSong] = []
    var tracksByID: [String: CatalogSong] = [:]
    var isLoadingTracks = true
    let highlightSongIDs: Set<String>
    let pendingSongID: String?

    var dataSource: UITableViewDiffableDataSource<AlbumSection, AlbumItem>!
    lazy var playlistMenuProvider = AddToPlaylistMenuProvider(
        playlistStore: environment.playlistStore,
        viewController: self
    )
    lazy var songExportPresenter = SongExportPresenter(
        viewController: self,
        lyricsStore: environment.lyricsCacheStore,
        locations: environment.paths,
        apiClient: environment.apiClient
    )
    lazy var songContextMenuProvider = SongContextMenuProvider(
        playlistMenuProvider: playlistMenuProvider,
        exportPresenter: songExportPresenter
    )
    private let albumNameLabel = CopyableLabel().then {
        $0.font = .systemFont(ofSize: 21, weight: .bold)
        $0.textAlignment = .center
        $0.numberOfLines = 0
    }

    private let artistNameLabel = CopyableLabel().then {
        $0.font = .systemFont(ofSize: 17, weight: .medium)
        $0.textColor = .tintColor
        $0.textAlignment = .center
    }

    private let metaLabel = CopyableLabel().then {
        $0.font = .preferredFont(forTextStyle: .caption1)
        $0.textColor = .secondaryLabel
        $0.textAlignment = .center
        $0.numberOfLines = 0
    }

    private let badgeStack = UIStackView().then {
        $0.axis = .horizontal
        $0.spacing = 6
        $0.alignment = .center
    }

    private let losslessBadge = makeAlbumBadgeView(text: String(localized: "Lossless"), icon: "waveform")
    private let atmosBadge = makeAlbumBadgeView(text: String(localized: "Dolby Atmos"), icon: "hifispeaker.2.fill")
    private let spatialBadge = makeAlbumBadgeView(text: String(localized: "Spatial"), icon: "ear.fill")

    init(album: CatalogAlbum, environment: AppEnvironment, highlightSongs: [String] = []) {
        self.album = album
        pendingSongID = nil
        self.environment = environment
        apiClient = environment.apiClient
        highlightSongIDs = Set(highlightSongs)
        super.init(tableStyle: .grouped)
    }

    init(song: CatalogSong, environment: AppEnvironment) {
        let attrs = CatalogAlbumAttributes(
            artistName: song.attributes.artistName,
            name: song.attributes.albumName ?? song.attributes.name,
            artwork: song.attributes.artwork
        )
        album = CatalogAlbum(id: "", type: "albums", href: nil, attributes: attrs, relationships: nil)
        pendingSongID = song.id
        self.environment = environment
        apiClient = environment.apiClient
        highlightSongIDs = [song.id]
        super.init(tableStyle: .grouped)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        view.accessibilityIdentifier = "detail.album"
        title = album.attributes.name
        navigationItem.largeTitleDisplayMode = .never

        configureDetailArtwork(placeholder: "square.stack.fill", allowsPreviewOnTap: true)
        configureNavBar()
        configureHeader()
        configureTableView()
        configureDataSource()
        populateHeader()
        loadTracks()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLibraryDidSync),
            name: .libraryDidSync,
            object: nil
        )
    }

    @MainActor deinit {
        NotificationCenter.default.removeObserver(self, name: .libraryDidSync, object: nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshDownloadStateUI()
    }

    @objc private func handleLibraryDidSync() {
        refreshDownloadStateUI()
    }

    func refreshDownloadStateUI() {
        tableView.reloadData()
        refreshNavBarMenu()
    }

    // MARK: - Nav Bar

    private func configureNavBar() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis.circle"),
            menu: buildAddMenu()
        )
    }

    func refreshNavBarMenu() {
        navigationItem.rightBarButtonItem?.menu = buildAddMenu()
    }

    var areAllTracksDownloaded: Bool {
        guard !tracks.isEmpty else { return false }
        return tracks.allSatisfy { environment.downloadStore.isDownloaded(trackID: $0.id) }
    }

    var downloadedTrackCount: Int {
        tracks.reduce(into: 0) { count, track in
            if environment.downloadStore.isDownloaded(trackID: track.id) {
                count += 1
            }
        }
    }

    func saveAlbumAsPlaylist() {
        let entries = playlistEntriesForCurrentTracks()
        guard !entries.isEmpty else { return }

        let playlist = environment.playlistStore.createPlaylist(name: album.attributes.name)
        entries.forEach { environment.playlistStore.addSong($0, to: playlist.id) }
        fetchLyricsInBackground(trackIDs: tracks.map(\.id), playlistID: playlist.id)
        refreshNavBarMenu()
    }

    func playlistEntriesForCurrentTracks() -> [PlaylistEntry] {
        tracks.map { track in
            track.playlistEntry(
                albumID: album.id,
                albumName: track.attributes.albumName ?? album.attributes.name
            )
        }
    }

    func saveToLibrary() {
        guard !tracks.isEmpty else { return }

        let requests = tracks.map { $0.downloadRequest(albumID: album.id, apiClient: environment.apiClient) }
        let result = environment.downloadManager.submitRequests(requests)
        DownloadSubmissionFeedbackPresenter.present(result)
    }

    func fetchLyricsInBackground(trackIDs: [String], playlistID: UUID) {
        guard !trackIDs.isEmpty else { return }
        Task { [weak self] in
            guard let self else { return }
            for trackID in trackIDs {
                do {
                    let lyrics = try await environment.lyricsService.fetchLyrics(for: trackID)
                    environment.playlistStore.updateLyrics(lyrics, trackID: trackID, playlistID: playlistID)
                } catch {
                    AppLog.info(self, "Lyrics unavailable for \(trackID)")
                }
            }
        }
    }

    func confirmDeleteTrack(_ track: CatalogSong) {
        ConfirmationAlertPresenter.present(
            on: self,
            title: String(localized: "Delete Song"),
            message: String(localized: "Delete \"\(track.attributes.name)\" from your saved songs? This cannot be undone."),
            confirmTitle: String(localized: "Delete Song")
        ) { [weak self] in
            self?.deleteTrack(track)
        }
    }

    private func deleteTrack(_ track: CatalogSong) {
        environment.musicLibraryTrackRemovalService.removeTrack(trackID: track.id)
        environment.playbackController.removeTracksFromQueue(trackIDs: [track.id])

        let hasRemainingDownloads = tracks.contains { $0.id != track.id && environment.downloadStore.isDownloaded(trackID: $0.id) }
        if !hasRemainingDownloads {
            navigationController?.popViewController(animated: true)
            return
        }

        refreshDownloadStateUI()
    }

    func saveTrackToLibrary(_ track: CatalogSong) {
        let request = track.downloadRequest(albumID: album.id, apiClient: environment.apiClient)
        let result = environment.downloadManager.submitRequests([request])
        DownloadSubmissionFeedbackPresenter.present(result)
    }

    func exportItem(for track: CatalogSong) -> SongExportItem? {
        guard let localTrack = environment.libraryDatabase.trackOrNil(byID: track.id) else {
            return nil
        }

        return localTrack.exportItem(
            paths: environment.paths,
            displayArtist: track.attributes.artistName,
            displayTitle: track.attributes.name,
            displayAlbumName: track.attributes.albumName ?? album.attributes.name,
            artworkURL: track.attributes.artwork?.imageURL(width: 600, height: 600)
        )
    }

    // MARK: - Header

    private func configureHeader() {
        badgeStack.addArrangedSubview(losslessBadge)
        badgeStack.addArrangedSubview(atmosBadge)
        badgeStack.addArrangedSubview(spatialBadge)
        losslessBadge.isHidden = true
        atmosBadge.isHidden = true
        spatialBadge.isHidden = true
        configureDetailHeader(
            arrangedSubviews: [albumNameLabel, artistNameLabel, metaLabel, badgeStack],
            artworkSize: 220,
            customSpacings: [
                (albumNameLabel, 4),
                (artistNameLabel, 4),
                (metaLabel, InterfaceStyle.Spacing.xSmall),
            ]
        )
    }

    private func populateHeader() {
        albumNameLabel.text = album.attributes.name
        artistNameLabel.text = album.attributes.artistName

        var meta: [String] = []
        if let genres = album.attributes.genreNames, let first = genres.first { meta.append(first) }
        if let date = album.attributes.releaseDate { meta.append(String(date.prefix(4))) }
        metaLabel.text = meta.joined(separator: " · ")

        configureBadges()
        let artworkURL = environment.apiClient.mediaURL(from: album.attributes.artwork?.url, width: 600, height: 600)
        artworkImageView.loadImage(url: artworkURL)
        invalidateHeaderLayout()
    }

    private func configureBadges() {
        let traits = album.attributes.audioTraits ?? []

        let showLossless = traits.contains("lossless")
        let showAtmos = traits.contains("atmos")
        let showSpatial = traits.contains("spatial") && !traits.contains("atmos")
        let showAny = showLossless || showAtmos || showSpatial

        InterfaceAnimation.springAnimate {
            self.losslessBadge.isHidden = !showLossless
            self.atmosBadge.isHidden = !showAtmos
            self.spatialBadge.isHidden = !showSpatial
            self.badgeStack.isHidden = !showAny
        }
    }

    // MARK: - Table View

    private func configureTableView() {
        tableView.delegate = self
        tableView.register(AlbumTrackCell.self, forCellReuseIdentifier: AlbumTrackCell.reuseID)
        tableView.register(
            AlbumTrackSkeletonCell.self, forCellReuseIdentifier: AlbumTrackSkeletonCell.reuseID
        )
        configureDetailTableView(backgroundColor: .systemBackground)
        configureDetailFooter(hidden: true)
    }

    private static let releaseDateParser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let releaseDateDisplay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter
    }()

    private func albumFooterText() -> String? {
        let attrs = album.attributes
        var lines: [String] = []

        if let date = attrs.releaseDate,
           let parsed = Self.releaseDateParser.date(from: date)
        {
            lines.append(Self.releaseDateDisplay.string(from: parsed))
        } else if let date = attrs.releaseDate {
            lines.append(date)
        }

        var detailParts: [String] = []
        let totalMillis = tracks.compactMap(\.attributes.durationInMillis).reduce(0, +)
        let trackCount = attrs.trackCount ?? tracks.count
        if trackCount > 0, totalMillis > 0 {
            let minutes = totalMillis / 1000 / 60
            detailParts.append(String(localized: "\(trackCount) songs, \(minutes) minutes"))
        }
        if let copyright = attrs.copyright {
            detailParts.append(copyright)
        }
        if let label = attrs.recordLabel {
            detailParts.append(label)
        }
        if !detailParts.isEmpty {
            lines.append(detailParts.joined(separator: " "))
        }

        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    private func updateFooter() {
        guard !isLoadingTracks else {
            updateFooterText(nil)
            return
        }
        updateFooterText(albumFooterText())
    }

    // MARK: - Diffable Data Source

    private func configureDataSource() {
        dataSource = UITableViewDiffableDataSource<AlbumSection, AlbumItem>(
            tableView: tableView
        ) {
            [weak self] (tableView: UITableView, indexPath: IndexPath, item: AlbumItem)
            -> UITableViewCell? in
            guard let self else { return UITableViewCell() }

            switch item {
            case .skeleton:
                let cell = tableView.dequeueReusableCell(
                    withIdentifier: AlbumTrackSkeletonCell.reuseID, for: indexPath
                )
                cell.selectionStyle = .none
                cell.isUserInteractionEnabled = false
                return cell

            case let .track(_, id, number):
                guard
                    let cell = tableView.dequeueReusableCell(
                        withIdentifier: AlbumTrackCell.reuseID, for: indexPath
                    ) as? AlbumTrackCell
                else {
                    return UITableViewCell()
                }
                if let track = tracksByID[id] {
                    let highlighted = highlightSongIDs.contains(id)
                    let downloaded = environment.downloadStore.isDownloaded(trackID: id)
                    cell.configure(number: number, track: track, highlighted: highlighted, downloaded: downloaded)
                }
                return cell
            }
        }

        dataSource.defaultRowAnimation = .fade
        applySnapshot()
    }

    private func applySnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<AlbumSection, AlbumItem>()

        snapshot.appendSections([.tracks])
        if isLoadingTracks {
            let count = 64
            snapshot.appendItems((0 ..< count).map { AlbumItem.skeleton(index: $0) }, toSection: .tracks)
        } else {
            let trackItems: [AlbumItem] = tracks.enumerated().map { index, track in
                let num = track.attributes.trackNumber ?? (index + 1)
                return AlbumItem.track(position: index, id: track.id, number: num)
            }
            snapshot.appendItems(trackItems, toSection: .tracks)
        }

        dataSource.apply(snapshot, animatingDifferences: !isLoadingTracks)
        updateFooter()
    }

    // MARK: - Load Tracks

    private func setTracks(_ newTracks: [CatalogSong]) {
        tracks = newTracks
        var duplicateTrackIDs = Set<String>()
        tracksByID = newTracks.reduce(into: [:]) { result, track in
            if result.updateValue(track, forKey: track.id) != nil {
                duplicateTrackIDs.insert(track.id)
            }
        }
        if !duplicateTrackIDs.isEmpty {
            AppLog.warning(self, "Album tracks contain duplicate identifiers count=\(duplicateTrackIDs.count) albumID=\(album.id)")
        }
        refreshNavBarMenu()
    }

    private func loadTracks() {
        let hasExistingTracks = album.relationships?.tracks?.data.isEmpty == false
        let needsEnrichment = album.attributes.artwork == nil && !album.id.isEmpty

        if hasExistingTracks {
            setTracks(album.relationships!.tracks!.data)
            isLoadingTracks = false
            applySnapshot()
            scrollToHighlightedSongIfNeeded()
            if !needsEnrichment { return }
        }

        Task { [weak self] in
            guard let self else { return }

            if let songID = pendingSongID {
                do {
                    guard let fullSong = try await apiClient.song(id: songID),
                          let resolvedAlbum = fullSong.relationships?.albums?.data.first
                    else {
                        AppLog.warning(self, "loadTracks resolveSong failed songID=\(songID)")
                        if !hasExistingTracks {
                            isLoadingTracks = false
                            applySnapshot()
                        }
                        return
                    }
                    album = resolvedAlbum
                    title = album.attributes.name
                    populateHeader()
                    invalidateHeaderLayout(animated: true)
                } catch {
                    if !hasExistingTracks {
                        isLoadingTracks = false
                        applySnapshot()
                    }
                    AppLog.error(self, "Failed to resolve album from song: \(error.localizedDescription)")
                    return
                }
            }

            do {
                guard let full = try await apiClient.album(id: album.id),
                      let trackData = full.relationships?.tracks?.data
                else {
                    AppLog.warning(self, "loadTracks fetchAlbum empty albumID=\(album.id)")
                    if !hasExistingTracks {
                        isLoadingTracks = false
                        applySnapshot()
                    }
                    return
                }
                album = full
                populateHeader()
                invalidateHeaderLayout(animated: true)
                if !hasExistingTracks {
                    isLoadingTracks = false
                    setTracks(trackData)
                    applySnapshot()
                    scrollToHighlightedSongIfNeeded()
                }
            } catch {
                if !hasExistingTracks {
                    isLoadingTracks = false
                    applySnapshot()
                }
                AppLog.error(self, "Failed to load album tracks: \(error.localizedDescription)")
            }
        }
    }

    private func scrollToHighlightedSongIfNeeded() {
        guard !highlightSongIDs.isEmpty else { return }
        let snapshot = dataSource.snapshot()
        for item in snapshot.itemIdentifiers(inSection: .tracks) {
            guard case let .track(_, id, _) = item, highlightSongIDs.contains(id),
                  let indexPath = dataSource.indexPath(for: item)
            else { continue }
            InterfaceAnimation.springAnimate {
                self.tableView.scrollToRow(at: indexPath, at: .middle, animated: false)
            }
            return
        }
    }
}
