//
//  SyncContentPickerViewController.swift
//  MuseAmp
//
//  Created by @Lakr233 on 2026/04/14.
//

import AlertController
import MuseAmpDatabaseKit
import SnapKit
import Then
import UIKit

final class SyncContentPickerViewController: UIViewController {
    nonisolated enum ContentTab: Int, CaseIterable {
        case albums = 0
        case songs = 1
        case playlists = 2

        var title: String {
            switch self {
            case .albums: String(localized: "Albums")
            case .songs: String(localized: "Songs")
            case .playlists: String(localized: "Playlists")
            }
        }
    }

    nonisolated enum Section: Hashable {
        case main
    }

    nonisolated enum Item: Hashable {
        case album(String)
        case song(String)
        case playlist(UUID)
    }

    let environment: AppEnvironment
    let emptySelectionMessage: String
    let checksLocalNetworkPermission: Bool
    let onConfirm: ([AudioTrackRecord], SyncContentPickerViewController) -> Void

    private var currentTab: ContentTab = .albums
    private var hasAppliedInitialSnapshot = false

    private var allAlbums: [AlbumGroup] = []
    private var albumsByID: [String: AlbumGroup] = [:]
    private var allTracks: [AudioTrackRecord] = []
    private var tracksByID: [String: AudioTrackRecord] = [:]
    private var allPlaylists: [Playlist] = []
    private var playlistsByID: [UUID: Playlist] = [:]

    private let segmentControl = UISegmentedControl(
        items: ContentTab.allCases.map(\.title),
    )
    private let tableView = UITableView(frame: UIScreen.main.bounds, style: .plain)
    private var dataSource: UITableViewDiffableDataSource<Section, Item>!

    private lazy var sendButton = UIBarButtonItem(
        image: UIImage(systemName: "paperplane.fill"),
        style: .done,
        target: self,
        action: #selector(sendTapped),
    )

    private lazy var moreButton: UIBarButtonItem = {
        let item = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis.circle"),
            style: .plain,
            target: nil,
            action: nil,
        )
        item.menu = buildMoreMenu()
        return item
    }()

    init(
        environment: AppEnvironment,
        title: String,
        emptySelectionMessage: String,
        checksLocalNetworkPermission: Bool,
        onConfirm: @escaping ([AudioTrackRecord], SyncContentPickerViewController) -> Void,
    ) {
        self.environment = environment
        self.emptySelectionMessage = emptySelectionMessage
        self.checksLocalNetworkPermission = checksLocalNetworkPermission
        self.onConfirm = onConfirm
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        configureNavigationBar()
        configureSegmentControl()
        configureTableView()
        configureDataSource()
        loadData()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if checksLocalNetworkPermission {
            checkLocalNetworkPermission()
        }
    }
}

// MARK: - Setup

private extension SyncContentPickerViewController {
    func configureNavigationBar() {
        navigationItem.rightBarButtonItems = [sendButton, moreButton]
        sendButton.tintColor = .tintColor
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            systemItem: .cancel,
            primaryAction: UIAction { [weak self] _ in
                self?.dismiss(animated: true)
            },
        )
    }

    func configureSegmentControl() {
        segmentControl.selectedSegmentIndex = currentTab.rawValue
        segmentControl.addTarget(self, action: #selector(segmentChanged), for: .valueChanged)
        view.addSubview(segmentControl)
        segmentControl.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide).offset(8)
            make.leading.trailing.equalToSuperview().inset(16)
        }
    }

    func configureTableView() {
        tableView.delegate = self
        tableView.allowsMultipleSelectionDuringEditing = true
        tableView.isEditing = true
        tableView.register(AmSongCell.self, forCellReuseIdentifier: AmSongCell.reuseID)
        tableView.register(AmMediaCell.self, forCellReuseIdentifier: AmMediaCell.reuseID)
        tableView.register(PlaylistCell.self, forCellReuseIdentifier: PlaylistCell.cellReuseID)
        tableView.tableFooterView = UIView()
        tableView.keyboardDismissMode = .onDrag
        tableView.applySoftEdgeEffects()

        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.top.equalTo(segmentControl.snp.bottom).offset(8)
            make.leading.trailing.bottom.equalToSuperview()
        }
    }

    func configureDataSource() {
        dataSource = UITableViewDiffableDataSource<Section, Item>(
            tableView: tableView,
        ) { [weak self] tableView, indexPath, item in
            guard let self else { return UITableViewCell() }

            switch item {
            case let .album(albumID):
                guard let album = albumsByID[albumID],
                      let cell = tableView.dequeueReusableCell(
                          withIdentifier: AmMediaCell.reuseID,
                          for: indexPath,
                      ) as? AmMediaCell
                else { return UITableViewCell() }

                let subtitle = [
                    album.artistName,
                    album.trackCount == 1
                        ? String(localized: "1 song")
                        : String(localized: "\(album.trackCount) songs"),
                ].joined(separator: " · ")

                cell.configure(
                    content: MediaRowContent(
                        title: album.albumTitle,
                        subtitle: subtitle,
                        artwork: ArtworkContent(placeholderIcon: "square.stack", cornerRadius: 6),
                    ),
                    accessory: .none,
                )
                let artworkTrackID = album.artworkTrackID ?? album.albumID
                let cacheURL = environment.paths.artworkCacheURL(for: artworkTrackID)
                MuseAmpImageView.diskLoadQueue.async { [weak cell] in
                    guard FileManager.default.fileExists(atPath: cacheURL.path) else { return }
                    DispatchQueue.main.async {
                        cell?.loadArtwork(url: cacheURL)
                    }
                }
                return cell

            case let .song(trackID):
                guard let track = tracksByID[trackID],
                      let cell = tableView.dequeueReusableCell(
                          withIdentifier: AmSongCell.reuseID,
                          for: indexPath,
                      ) as? AmSongCell
                else { return UITableViewCell() }

                let cacheURL = environment.paths.artworkCacheURL(for: track.trackID)
                cell.configure(content: SongRowContent(audioTrack: track))
                MuseAmpImageView.diskLoadQueue.async { [weak cell] in
                    guard FileManager.default.fileExists(atPath: cacheURL.path) else { return }
                    DispatchQueue.main.async {
                        cell?.loadArtwork(url: cacheURL)
                    }
                }
                return cell

            case let .playlist(playlistID):
                guard let playlist = playlistsByID[playlistID],
                      let cell = tableView.dequeueReusableCell(
                          withIdentifier: PlaylistCell.cellReuseID,
                          for: indexPath,
                      ) as? PlaylistCell
                else { return UITableViewCell() }

                let songCount = playlist.songs.count
                let subtitle = songCount == 1
                    ? String(localized: "1 song")
                    : String(localized: "\(songCount) songs")

                cell.configure(
                    with: playlist,
                    subtitle: subtitle,
                    apiClient: environment.apiClient,
                    artworkCache: environment.playlistCoverArtworkCache,
                    paths: environment.paths,
                )
                cell.setAccessory(.none)
                return cell
            }
        }
    }
}

// MARK: - Data Loading

private extension SyncContentPickerViewController {
    func loadData() {
        Task { @MainActor [weak self] in
            guard let self else { return }

            let database = environment.libraryDatabase
            let store = environment.playlistStore

            let albums: [AlbumGroup]
            let tracks: [AudioTrackRecord]
            do {
                (albums, tracks) = try await Task.detached(priority: .userInitiated) {
                    let albums = try database.allAlbums().sorted {
                        $0.albumTitle.localizedCaseInsensitiveCompare($1.albumTitle) == .orderedAscending
                    }
                    let tracks = try database.allTracks().sorted {
                        $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                    }
                    return (albums, tracks)
                }.value
            } catch {
                AppLog.error(self, "loadData failed error=\(error)")
                return
            }

            allAlbums = albums
            albumsByID = Dictionary(uniqueKeysWithValues: albums.map { ($0.albumID, $0) })
            allTracks = tracks
            tracksByID = Dictionary(uniqueKeysWithValues: tracks.map { ($0.trackID, $0) })
            allPlaylists = store.playlists
            playlistsByID = Dictionary(uniqueKeysWithValues: allPlaylists.map { ($0.id, $0) })

            applySnapshot()
        }
    }

    func applySnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.main])

        switch currentTab {
        case .albums:
            snapshot.appendItems(allAlbums.map { .album($0.albumID) })
        case .songs:
            snapshot.appendItems(allTracks.map { .song($0.trackID) })
        case .playlists:
            snapshot.appendItems(allPlaylists.map { .playlist($0.id) })
        }

        let animate = hasAppliedInitialSnapshot && view.window != nil
        dataSource.apply(snapshot, animatingDifferences: animate)
        hasAppliedInitialSnapshot = true
    }
}

// MARK: - Local Network Permission

private extension SyncContentPickerViewController {
    func checkLocalNetworkPermission() {
        let hostName = ProcessInfo.processInfo.hostName
        let denied = hostName.isEmpty || hostName.lowercased() == "localhost"
        guard denied else { return }

        let alert = AlertViewController(
            title: String(localized: "Local Network Access Required"),
            message: String(localized: "Sending music to Apple TV requires local network access. Enable it in Settings for Muse Amp."),
        ) { [weak self] context in
            context.addAction(title: String(localized: "Open Settings"), attribute: .accent) {
                context.dispose {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                    self?.dismiss(animated: true)
                }
            }
        }
        present(alert, animated: true)
    }
}

// MARK: - Actions

private extension SyncContentPickerViewController {
    @objc func segmentChanged() {
        guard let tab = ContentTab(rawValue: segmentControl.selectedSegmentIndex) else { return }
        currentTab = tab
        if let selectedRows = tableView.indexPathsForSelectedRows {
            for indexPath in selectedRows {
                tableView.deselectRow(at: indexPath, animated: false)
            }
        }
        hasAppliedInitialSnapshot = false
        applySnapshot()
    }

    @objc func sendTapped() {
        let selectedTracks = resolveSelectedTracks()
        guard !selectedTracks.isEmpty else {
            let alert = AlertViewController(
                title: String(localized: "No Selection"),
                message: emptySelectionMessage,
            ) { context in
                context.addAction(title: String(localized: "OK"), attribute: .accent) {
                    context.dispose()
                }
            }
            present(alert, animated: true)
            return
        }

        onConfirm(selectedTracks, self)
    }

    func buildMoreMenu() -> UIMenu {
        UIMenu(children: [
            UIAction(
                title: String(localized: "Select All"),
                image: UIImage(systemName: "checkmark.circle"),
            ) { [weak self] _ in
                self?.selectAllCurrentList()
            },
            UIAction(
                title: String(localized: "Deselect All"),
                image: UIImage(systemName: "xmark.circle"),
            ) { [weak self] _ in
                self?.deselectAllCurrentList()
            },
        ])
    }

    func selectAllCurrentList() {
        let totalRows = tableView.numberOfRows(inSection: 0)
        guard totalRows > 0 else { return }
        for row in 0 ..< totalRows {
            tableView.selectRow(at: IndexPath(row: row, section: 0), animated: false, scrollPosition: .none)
        }
    }

    func deselectAllCurrentList() {
        guard let selectedRows = tableView.indexPathsForSelectedRows else { return }
        for indexPath in selectedRows {
            tableView.deselectRow(at: indexPath, animated: false)
        }
    }

    func resolveSelectedTracks() -> [AudioTrackRecord] {
        guard let selectedIndexPaths = tableView.indexPathsForSelectedRows else { return [] }
        let selectedItems = selectedIndexPaths.compactMap { dataSource.itemIdentifier(for: $0) }

        var tracks: [AudioTrackRecord] = []
        var seenIDs = Set<String>()

        for item in selectedItems {
            switch item {
            case let .album(albumID):
                let albumTracks = (try? environment.libraryDatabase.databaseManager.tracks(inAlbumID: albumID)) ?? []
                for track in albumTracks where seenIDs.insert(track.trackID).inserted {
                    tracks.append(track)
                }
            case let .song(trackID):
                if let track = tracksByID[trackID], seenIDs.insert(track.trackID).inserted {
                    tracks.append(track)
                }
            case let .playlist(playlistID):
                if let playlist = playlistsByID[playlistID] {
                    for entry in playlist.songs {
                        if let track = tracksByID[entry.trackID],
                           seenIDs.insert(track.trackID).inserted
                        {
                            tracks.append(track)
                        }
                    }
                }
            }
        }

        return tracks
    }
}

// MARK: - UITableViewDelegate

extension SyncContentPickerViewController: UITableViewDelegate {
    func tableView(_: UITableView, shouldBeginMultipleSelectionInteractionAt _: IndexPath) -> Bool {
        true
    }

    func tableView(_: UITableView, didBeginMultipleSelectionInteractionAt _: IndexPath) {}
}
