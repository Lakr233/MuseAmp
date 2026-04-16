//
//  ArtistDetailViewController.swift
//  MuseAmp
//
//  Created by @libr on 2026/04/16.
//

import MuseAmpDatabaseKit
import SnapKit
import SubsonicClientKit
import Then
import UIKit

nonisolated enum ArtistDetailSection: Int, Hashable {
    case header
    case songs
    case albums
}

nonisolated enum ArtistDetailItem: Hashable {
    case header
    case loading
    case song(String)
    case songsShowMore
    case album(String)
    case albumsShowMore
}

@MainActor
final class ArtistDetailViewController: MediaDetailViewController {
    private nonisolated enum Layout {
        static let previewSongCount = 5
        static let previewAlbumCount = 5
    }

    var artist: CatalogArtist
    let environment: AppEnvironment
    let apiClient: APIClient
    var songs: [CatalogSong] = []
    var songsByID: [String: CatalogSong] = [:]
    var albums: [CatalogAlbum] = []
    var albumsByID: [String: CatalogAlbum] = [:]
    var resolvedSongAlbumIDs: Set<String> = []
    var isLoadingArtist = true
    var isLoadingSongs = false
    var requestedSongCount = Layout.previewSongCount
    var requestedAlbumCount = Layout.previewAlbumCount
    private var songResolutionTask: Task<Void, Never>?
    private var hasAppliedInitialSnapshot = false

    private let emptyStateView = EmptyStateView(
        icon: "music.note.list",
        title: String(localized: "No Albums Yet"),
        subtitle: String(localized: "This artist has no albums yet."),
    ).then { $0.isHidden = true }

    lazy var albumNavigationHelper = AlbumNavigationHelper(
        environment: environment,
        viewController: self,
    )

    var dataSource: UITableViewDiffableDataSource<ArtistDetailSection, ArtistDetailItem>!

    init(artist: CatalogArtist, environment: AppEnvironment) {
        self.artist = artist
        self.environment = environment
        apiClient = environment.apiClient
        super.init(tableStyle: .grouped)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        view.accessibilityIdentifier = "detail.artist"
        title = artist.attributes.name
        navigationItem.largeTitleDisplayMode = .never

        configureTableView()
        configureDataSource()
        loadArtistDetail()
    }

    private func configureTableView() {
        tableView.delegate = self
        tableView.register(ArtistHeaderCell.self, forCellReuseIdentifier: ArtistHeaderCell.reuseID)
        tableView.register(AmSongCell.self, forCellReuseIdentifier: AmSongCell.reuseID)
        tableView.register(AmMediaCell.self, forCellReuseIdentifier: AmMediaCell.reuseID)
        tableView.register(ShowMoreCell.self, forCellReuseIdentifier: ShowMoreCell.reuseID)
        tableView.register(SearchLoadingCell.self, forCellReuseIdentifier: SearchLoadingCell.reuseID)
        tableView.register(SearchSectionHeaderView.self, forHeaderFooterViewReuseIdentifier: SearchSectionHeaderView.reuseID)
        configureDetailTableView(backgroundColor: .systemBackground)

        view.addSubview(emptyStateView)
        emptyStateView.snp.makeConstraints { make in
            make.center.equalTo(view.safeAreaLayoutGuide)
            make.leading.trailing.equalTo(view.safeAreaLayoutGuide).inset(24)
        }
    }

    private func configureDataSource() {
        dataSource = UITableViewDiffableDataSource<ArtistDetailSection, ArtistDetailItem>(
            tableView: tableView,
        ) { [weak self] tableView, indexPath, item in
            guard let self else { return UITableViewCell() }

            switch item {
            case .header:
                guard let cell = tableView.dequeueReusableCell(
                    withIdentifier: ArtistHeaderCell.reuseID,
                    for: indexPath,
                ) as? ArtistHeaderCell else {
                    return UITableViewCell()
                }
                cell.configure(
                    name: artist.attributes.name,
                    subtitle: nil,
                    artworkURL: apiClient.mediaURL(from: artist.attributes.artwork?.url, width: 600, height: 600),
                )
                cell.selectionStyle = .none
                return cell
            case .loading:
                guard let cell = tableView.dequeueReusableCell(
                    withIdentifier: SearchLoadingCell.reuseID,
                    for: indexPath,
                ) as? SearchLoadingCell else {
                    return UITableViewCell()
                }
                cell.startAnimating()
                cell.selectionStyle = .none
                return cell
            case let .song(id):
                guard let cell = tableView.dequeueReusableCell(
                    withIdentifier: AmSongCell.reuseID,
                    for: indexPath,
                ) as? AmSongCell else {
                    return UITableViewCell()
                }
                guard let song = songsByID[id] else { return cell }
                let subtitle = song.attributes.albumName.nilIfEmpty ?? song.attributes.artistName
                cell.configure(
                    content: SongRowContent(
                        title: song.attributes.name.sanitizedTrackTitle,
                        subtitle: subtitle,
                        trailingText: song.attributes.durationInMillis.map { formattedDuration(millis: $0) },
                        artworkURL: apiClient.mediaURL(from: song.attributes.artwork?.url, width: 88, height: 88),
                        showsDownloadedIndicator: environment.downloadStore.isDownloaded(trackID: song.id),
                    ),
                )
                return cell
            case .songsShowMore:
                guard let cell = tableView.dequeueReusableCell(
                    withIdentifier: ShowMoreCell.reuseID,
                    for: indexPath,
                ) as? ShowMoreCell else {
                    return UITableViewCell()
                }
                cell.configure(isLoading: isLoadingSongs)
                return cell
            case let .album(id):
                guard let cell = tableView.dequeueReusableCell(
                    withIdentifier: AmMediaCell.reuseID,
                    for: indexPath,
                ) as? AmMediaCell else {
                    return UITableViewCell()
                }
                guard let album = albumsByID[id] else { return cell }
                cell.configure(
                    content: MediaRowContent(
                        title: album.attributes.name,
                        subtitle: albumSubtitle(for: album),
                        artwork: ArtworkContent(
                            placeholderIcon: "square.stack.fill",
                            cornerRadius: 6,
                        ),
                    ),
                )
                cell.loadArtwork(url: apiClient.mediaURL(from: album.attributes.artwork?.url, width: 88, height: 88))
                return cell
            case .albumsShowMore:
                guard let cell = tableView.dequeueReusableCell(
                    withIdentifier: ShowMoreCell.reuseID,
                    for: indexPath,
                ) as? ShowMoreCell else {
                    return UITableViewCell()
                }
                cell.configure(isLoading: false)
                return cell
            }
        }
        dataSource.defaultRowAnimation = .fade
        applySnapshot()
    }

    func applySnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<ArtistDetailSection, ArtistDetailItem>()
        snapshot.appendSections([.header])
        snapshot.appendItems([.header], toSection: .header)

        if shouldShowSongsSection {
            snapshot.appendSections([.songs])
            if visibleSongs.isEmpty {
                snapshot.appendItems([.loading], toSection: .songs)
            } else {
                snapshot.appendItems(visibleSongs.map { .song($0.id) }, toSection: .songs)
                if canShowMoreSongs {
                    snapshot.appendItems([.songsShowMore], toSection: .songs)
                }
            }
        }

        if shouldShowAlbumsSection {
            snapshot.appendSections([.albums])
            snapshot.appendItems(visibleAlbums.map { .album($0.id) }, toSection: .albums)
            if canShowMoreAlbums {
                snapshot.appendItems([.albumsShowMore], toSection: .albums)
            }
        }

        let shouldAnimate = hasAppliedInitialSnapshot && view.window != nil
        dataSource.apply(snapshot, animatingDifferences: shouldAnimate)
        hasAppliedInitialSnapshot = true
        updateEmptyState()
    }

    private func updateEmptyState() {
        emptyStateView.isHidden = isLoadingArtist || isLoadingSongs || !songs.isEmpty || !albums.isEmpty
    }

    private func loadArtistDetail() {
        guard !artist.id.isEmpty else {
            isLoadingArtist = false
            applySnapshot()
            return
        }

        Task { [weak self] in
            guard let self else { return }
            do {
                guard let response = try await apiClient.artist(id: artist.id) else {
                    isLoadingArtist = false
                    applySnapshot()
                    return
                }

                artist = mergedArtist(current: artist, detail: response.artist)
                title = artist.attributes.name
                setAlbums(response.albums)
                isLoadingArtist = false
                refreshHeader()
                applySnapshot()
                startSongResolutionIfNeeded()
            } catch {
                isLoadingArtist = false
                applySnapshot()
                AppLog.error(self, "Failed to load artist detail: \(error.localizedDescription)")
            }
        }
    }

    private func setAlbums(_ albums: [CatalogAlbum]) {
        self.albums = deduplicatedAlbums(albums)
        albumsByID = Dictionary(uniqueKeysWithValues: self.albums.map { ($0.id, $0) })
        songs.removeAll(keepingCapacity: true)
        songsByID.removeAll(keepingCapacity: true)
        resolvedSongAlbumIDs.removeAll(keepingCapacity: true)
        requestedSongCount = Layout.previewSongCount
        requestedAlbumCount = Layout.previewAlbumCount

        for album in self.albums where album.relationships?.tracks?.data.isEmpty == false {
            resolvedSongAlbumIDs.insert(album.id)
            appendSongs(from: album)
        }
    }

    /// The header starts from the search stub artist, so it needs a targeted refresh
    /// after `getArtist` fills in the canonical artwork URL.
    private func refreshHeader() {
        var snapshot = dataSource.snapshot()
        snapshot.reconfigureItems([.header])
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func deduplicatedAlbums(_ albums: [CatalogAlbum]) -> [CatalogAlbum] {
        var seen = Set<String>()
        return albums.filter { seen.insert($0.id).inserted }
    }

    private var visibleSongs: [CatalogSong] {
        Array(songs.prefix(requestedSongCount))
    }

    private var visibleAlbums: [CatalogAlbum] {
        Array(albums.prefix(requestedAlbumCount))
    }

    private var shouldShowSongsSection: Bool {
        isLoadingArtist || isLoadingSongs || !songs.isEmpty
    }

    private var shouldShowAlbumsSection: Bool {
        !albums.isEmpty
    }

    private var canShowMoreSongs: Bool {
        songs.count > requestedSongCount || resolvedSongAlbumIDs.count < albums.count
    }

    private var canShowMoreAlbums: Bool {
        albums.count > requestedAlbumCount
    }

    func showMoreSongs() {
        requestedSongCount += Layout.previewSongCount
        applySnapshot()
        startSongResolutionIfNeeded()
    }

    func showMoreAlbums() {
        requestedAlbumCount += Layout.previewAlbumCount
        applySnapshot()
    }

    func startSongResolutionIfNeeded() {
        guard !isLoadingArtist else { return }
        guard !isLoadingSongs else { return }
        guard songs.count < requestedSongCount else { return }
        guard resolvedSongAlbumIDs.count < albums.count else { return }

        songResolutionTask = Task { [weak self] in
            await self?.loadSongsUntilRequestedCount()
        }
    }

    private func loadSongsUntilRequestedCount() async {
        guard !isLoadingSongs else { return }
        isLoadingSongs = true
        applySnapshot()

        defer {
            isLoadingSongs = false
            songResolutionTask = nil
            applySnapshot()
            startSongResolutionIfNeeded()
        }

        while songs.count < requestedSongCount,
              let album = nextAlbumForSongResolution()
        {
            resolvedSongAlbumIDs.insert(album.id)
            do {
                let resolvedAlbum = try await apiClient.album(id: album.id) ?? album
                mergeResolvedAlbum(resolvedAlbum)
            } catch {
                AppLog.error(
                    self,
                    "Failed to load artist songs artistID=\(artist.id) albumID=\(album.id): \(error.localizedDescription)",
                )
            }
        }
    }

    private func nextAlbumForSongResolution() -> CatalogAlbum? {
        albums.first { !resolvedSongAlbumIDs.contains($0.id) }
    }

    private func mergeResolvedAlbum(_ album: CatalogAlbum) {
        if let index = albums.firstIndex(where: { $0.id == album.id }) {
            albums[index] = album
        }
        albumsByID[album.id] = album
        appendSongs(from: album)
    }

    private func appendSongs(from album: CatalogAlbum) {
        guard let tracks = album.relationships?.tracks?.data else { return }

        for song in tracks where songMatchesCurrentArtist(song) {
            guard songsByID[song.id] == nil else { continue }
            songs.append(song)
            songsByID[song.id] = song
        }
    }

    private func songMatchesCurrentArtist(_ song: CatalogSong) -> Bool {
        if song.relationships?.artists?.data.contains(where: { $0.id == artist.id }) == true {
            return true
        }
        return song.attributes.artistName.localizedCaseInsensitiveCompare(artist.attributes.name) == .orderedSame
    }

    private func mergedArtist(current: CatalogArtist, detail: CatalogArtist) -> CatalogArtist {
        let artwork = detail.attributes.artwork ?? current.attributes.artwork
        let name = detail.attributes.name.isEmpty ? current.attributes.name : detail.attributes.name
        return CatalogArtist(
            id: detail.id,
            type: detail.type,
            href: detail.href,
            attributes: CatalogArtistAttributes(
                name: name,
                url: detail.attributes.url ?? current.attributes.url,
                artwork: artwork,
            ),
        )
    }

    private func albumSubtitle(for album: CatalogAlbum) -> String? {
        var parts: [String] = []
        if let releaseDate = album.attributes.releaseDate {
            parts.append(String(releaseDate.prefix(4)))
        }
        if !album.attributes.artistName.isEmpty, album.attributes.artistName != artist.attributes.name {
            parts.append(album.attributes.artistName)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
