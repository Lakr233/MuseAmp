//
//  PlaylistDetailViewController.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import AlertController
import AmMusicDatabaseKit
import Combine
import ConfigurableKit
import Then
import UIKit

nonisolated enum PlaylistDetailSection: Int, Hashable {
    case header
    case tracks
    case footer
}

nonisolated enum PlaylistDetailItem: Hashable {
    case header
    case song(entryID: String, trackID: String)
    case footer
}

@MainActor
final class PlaylistDetailViewController: MediaDetailViewController, UITableViewDelegate, UITableViewDragDelegate {
    let playlistID: UUID
    let store: PlaylistStore
    let environment: AppEnvironment?

    private var playlistsDidChangeObserver: NSObjectProtocol?
    private var cancellables: Set<AnyCancellable> = []

    var playlist: Playlist? {
        store.playlist(for: playlistID)
    }

    var dataSource: PlaylistDetailDiffableDataSource!
    var headerCoverTask: Task<Void, Never>?
    var localArtworkPrefetchTask: Task<Void, Never>?
    var headerArtworkImage: UIImage?

    lazy var playlistMenuProvider = AddToPlaylistMenuProvider(
        playlistStore: store,
        viewController: self,
    )
    lazy var playbackMenuProvider = environment.map {
        PlaybackMenuProvider(playbackController: $0.playbackController)
    }

    lazy var songExportPresenter = SongExportPresenter(
        viewController: self,
        lyricsStore: environment?.lyricsCacheStore,
        locations: environment?.paths,
        apiClient: environment?.apiClient,
    )
    lazy var songContextMenuProvider = SongContextMenuProvider(
        playlistMenuProvider: playlistMenuProvider,
        exportPresenter: songExportPresenter,
    )
    lazy var coverPreviewPresenter = ImageQuickLookPreviewPresenter(viewController: self)
    lazy var albumNavigationHelper: AlbumNavigationHelper? = environment.map {
        AlbumNavigationHelper(environment: $0, viewController: self)
    }

    // MARK: - Init

    init(playlistID: UUID, environment: AppEnvironment) {
        self.playlistID = playlistID
        store = environment.playlistStore
        self.environment = environment
        super.init(tableStyle: .plain)
    }

    init(playlistID: UUID, store: PlaylistStore) {
        self.playlistID = playlistID
        self.store = store
        environment = nil
        super.init(tableStyle: .plain)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        view.accessibilityIdentifier = "playlist.detail"
        title = playlist?.name ?? String(localized: "Playlist")

        updateOptionsMenu()
        configureTableView()
        configureDataSource()
        populateHeader()
        observePlaylistChanges()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLibraryDidSync),
            name: .libraryDidSync,
            object: nil,
        )

        ConfigurableKit.publisher(
            forKey: AppPreferences.cleanSongTitleKey, type: Bool.self,
        )
        .dropFirst()
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in self?.tableView.reloadData() }
        .store(in: &cancellables)
    }

    @MainActor deinit {
        headerCoverTask?.cancel()
        localArtworkPrefetchTask?.cancel()
        if let playlistsDidChangeObserver {
            NotificationCenter.default.removeObserver(playlistsDidChangeObserver)
        }
        NotificationCenter.default.removeObserver(self, name: .libraryDidSync, object: nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshDownloadStateUI()
    }

    override func setEditing(_ editing: Bool, animated: Bool) {
        super.setEditing(editing, animated: animated)
        tableView.setEditing(editing, animated: animated)
    }

    @objc private func handleLibraryDidSync() {
        refreshDownloadStateUI()
    }

    private func observePlaylistChanges() {
        playlistsDidChangeObserver = NotificationCenter.default.addObserver(
            forName: .playlistsDidChange,
            object: store,
            queue: .main,
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handlePlaylistStoreDidChange()
            }
        }
    }

    private func handlePlaylistStoreDidChange() {
        guard store.playlist(for: playlistID) != nil else {
            if navigationController?.topViewController === self {
                navigationController?.popViewController(animated: true)
            }
            return
        }
        refreshDownloadStateUI()
    }

    func refreshDownloadStateUI() {
        store.reload()
        populateHeader()
        applySnapshot()
        prefetchLocalArtworkIfNeeded()
        updateOptionsMenu()
    }

    // MARK: - Header

    func populateHeader() {
        guard let playlist else {
            headerArtworkImage = nil
            reloadHeaderCell()
            return
        }
        title = playlist.name

        headerCoverTask?.cancel()
        if let coverData = playlist.coverImageData, let image = UIImage(data: coverData) {
            AppLog.verbose(self, "populateHeader playlistID=\(playlist.id) using custom cover bytes=\(coverData.count)")
            headerArtworkImage = image
            reloadHeaderCell()
            return
        }

        guard !playlist.songs.isEmpty else {
            AppLog.verbose(self, "populateHeader playlistID=\(playlist.id) no songs reset artwork")
            headerArtworkImage = nil
            reloadHeaderCell()
            return
        }

        AppLog.verbose(self, "populateHeader playlistID=\(playlist.id) generating artwork")
        headerArtworkImage = nil
        reloadHeaderCell()
        headerCoverTask = Task { @MainActor [weak self, playlist] in
            guard let self,
                  let image = await generatedCoverImage(for: playlist, sideLength: 200)
            else { return }

            guard !Task.isCancelled else {
                AppLog.verbose(self, "header cover task cancelled playlistID=\(playlist.id)")
                return
            }
            guard playlistID == playlist.id else {
                AppLog.verbose(
                    self,
                    "header cover task dropped playlistID=\(playlist.id) current=\(playlistID.uuidString)",
                )
                return
            }
            AppLog.verbose(self, "header cover task applied playlistID=\(playlist.id)")
            headerArtworkImage = image
            reloadHeaderCell()
        }
    }

    func reloadHeaderCell() {
        guard let dataSource, var snapshot = Optional(dataSource.snapshot()),
              snapshot.indexOfSection(.header) != nil
        else { return }
        snapshot.reconfigureItems([.header])
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    // MARK: - Table View

    private func configureTableView() {
        tableView.delegate = self
        tableView.register(PlaylistHeaderCell.self, forCellReuseIdentifier: PlaylistHeaderCell.reuseID)
        tableView.register(AmSongCell.self, forCellReuseIdentifier: AmSongCell.reuseID)
        tableView.register(DetailFooterCell.self, forCellReuseIdentifier: DetailFooterCell.reuseID)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 64
        tableView.sectionHeaderTopPadding = 0

        tableView.dragInteractionEnabled = true
        tableView.dragDelegate = self

        configureDetailTableView(backgroundColor: .systemBackground)
    }

    private func footerText() -> String? {
        guard let playlist else { return nil }

        let songCount = playlist.songs.count
        guard songCount > 0 else { return nil }

        let totalMillis = playlist.songs.compactMap(\.durationMillis).reduce(0, +)
        let songCountText = songCount == 1 ? String(localized: "1 song") : String(localized: "\(songCount) songs")

        if totalMillis > 0 {
            let minutes = totalMillis / 1000 / 60
            return String(localized: "\(songCountText), \(minutes) minutes")
        } else {
            return songCountText
        }
    }

    // MARK: - Diffable Data Source

    private func configureDataSource() {
        dataSource = PlaylistDetailDiffableDataSource(
            tableView: tableView,
            playlistID: playlistID,
            store: store,
        ) { [weak self] tableView, indexPath, item -> UITableViewCell? in
            guard let self else { return UITableViewCell() }

            switch item {
            case .header:
                guard let cell = tableView.dequeueReusableCell(
                    withIdentifier: PlaylistHeaderCell.reuseID, for: indexPath,
                ) as? PlaylistHeaderCell else {
                    return UITableViewCell()
                }
                if let image = headerArtworkImage {
                    cell.artworkImageView.setImage(image)
                } else {
                    cell.artworkImageView.reset()
                }
                cell.selectionStyle = .none
                return cell

            case let .song(entryID, _):
                let cell = tableView.dequeueReusableCell(
                    withIdentifier: AmSongCell.reuseID,
                    for: indexPath,
                ) as! AmSongCell
                guard let songs = playlist?.songs,
                      let song = songs.first(where: { $0.entryID == entryID })
                else {
                    return cell
                }
                cell.configure(with: song, artworkURL: artworkURL(for: song))
                cell.setDownloadedIndicatorVisible(isSongDownloaded(song))
                return cell

            case .footer:
                guard let cell = tableView.dequeueReusableCell(
                    withIdentifier: DetailFooterCell.reuseID, for: indexPath,
                ) as? DetailFooterCell else {
                    return UITableViewCell()
                }
                cell.configure(text: footerText())
                cell.selectionStyle = .none
                cell.isUserInteractionEnabled = false
                return cell
            }
        }

        dataSource.defaultRowAnimation = .fade
        applySnapshot()
    }

    func applySnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<PlaylistDetailSection, PlaylistDetailItem>()

        snapshot.appendSections([.header])
        snapshot.appendItems([.header], toSection: .header)

        snapshot.appendSections([.tracks])
        if let songs = playlist?.songs {
            let songItems: [PlaylistDetailItem] = songs.map { .song(entryID: $0.entryID, trackID: $0.trackID) }
            snapshot.appendItems(songItems, toSection: .tracks)
        }

        let hasFooterContent = footerText() != nil
        if hasFooterContent {
            snapshot.appendSections([.footer])
            snapshot.appendItems([.footer], toSection: .footer)
        }

        dataSource.apply(snapshot, animatingDifferences: false)
    }

    // MARK: - UITableViewDelegate

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard environment != nil,
              let item = dataSource.itemIdentifier(for: indexPath),
              case let .song(entryID, _) = item,
              let songs = playlist?.songs,
              let songIndex = songs.firstIndex(where: { $0.entryID == entryID })
        else { return }
        playSong(at: songIndex)
    }

    func tableView(_: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return false }
        if case .song = item { return true }
        return false
    }

    func tableView(
        _: UITableView,
        contextMenuConfigurationForRowAt indexPath: IndexPath,
        point _: CGPoint,
    ) -> UIContextMenuConfiguration? {
        guard let item = dataSource.itemIdentifier(for: indexPath),
              case let .song(entryID, _) = item,
              let songs = playlist?.songs,
              let song = songs.first(where: { $0.entryID == entryID })
        else { return nil }

        return UIContextMenuConfiguration(identifier: indexPath as NSIndexPath, previewProvider: nil) { [weak self] _ in
            guard let self else { return nil }
            let removeAction = UIAction(
                title: String(localized: "Remove"),
                image: UIImage(systemName: "minus.circle"),
            ) { [weak self] _ in
                self?.confirmRemove(song: song)
            }

            var destructiveActions: [UIMenuElement] = [removeAction]
            if environment != nil {
                destructiveActions.append(UIAction(
                    title: String(localized: "Delete Song"),
                    image: UIImage(systemName: "trash"),
                    attributes: .destructive,
                ) { [weak self] _ in
                    self?.confirmDeleteSong(song)
                })
            }

            return songContextMenuProvider.menu(
                title: song.title,
                for: song,
                context: .playlist,
                configuration: .init(
                    availablePlaylists: { [weak self] in self?.availableTargetPlaylists(for: song) ?? [] },
                    showInAlbum: environment == nil ? nil : { [weak self] in
                        self?.openAlbum(for: song)
                    },
                    exportItems: { [weak self] in
                        guard let item = self?.exportItem(for: song) else { return [] }
                        return [item]
                    },
                    primaryActions: playbackMenuProvider?.songPrimaryActions(
                        trackProvider: { [weak self] in
                            self?.playbackTrack(for: song)
                        },
                        queueProvider: { [weak self] in
                            self?.playlistPlaybackTracks() ?? []
                        },
                        sourceProvider: { [weak self] in
                            .playlist(self?.playlistID ?? UUID())
                        },
                    ) ?? [],
                    destructiveActions: destructiveActions,
                ),
            )
        }
    }

    func tableView(
        _: UITableView,
        previewForHighlightingContextMenuWithConfiguration configuration: UIContextMenuConfiguration,
    ) -> UITargetedPreview? {
        CellContextMenuPreviewHelper.targetedPreview(for: configuration, in: tableView)
    }

    func tableView(
        _: UITableView,
        previewForDismissingContextMenuWithConfiguration configuration: UIContextMenuConfiguration,
    ) -> UITargetedPreview? {
        CellContextMenuPreviewHelper.targetedPreview(for: configuration, in: tableView)
    }

    func tableView(
        _: UITableView,
        targetIndexPathForMoveFromRowAt sourceIndexPath: IndexPath,
        toProposedIndexPath proposedDestinationIndexPath: IndexPath,
    ) -> IndexPath {
        guard let tracksSection = dataSource.snapshot().indexOfSection(.tracks) else {
            return sourceIndexPath
        }
        if proposedDestinationIndexPath.section < tracksSection {
            return IndexPath(row: 0, section: tracksSection)
        }
        if proposedDestinationIndexPath.section > tracksSection {
            let trackCount = dataSource.snapshot().numberOfItems(inSection: .tracks)
            return IndexPath(row: max(trackCount - 1, 0), section: tracksSection)
        }
        return proposedDestinationIndexPath
    }

    // MARK: - UITableViewDragDelegate

    func tableView(_: UITableView, itemsForBeginning _: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
        guard let item = dataSource.itemIdentifier(for: indexPath),
              case let .song(entryID, _) = item,
              let songs = playlist?.songs,
              let song = songs.first(where: { $0.entryID == entryID }),
              let exportItem = exportItem(for: song)
        else { return [] }

        let fileExtension = exportItem.sourceURL.pathExtension
        let fileName = fileExtension.isEmpty
            ? exportItem.preferredFileBaseName
            : "\(exportItem.preferredFileBaseName).\(fileExtension)"

        let provider = NSItemProvider()
        provider.suggestedName = fileName
        provider.registerFileRepresentation(
            forTypeIdentifier: "public.audio",
            fileOptions: [],
            visibility: .all,
        ) { completion in
            completion(exportItem.sourceURL, false, nil)
            return nil
        }

        let dragItem = UIDragItem(itemProvider: provider)
        dragItem.localObject = song
        return [dragItem]
    }
}

// MARK: - PlaylistDetailDiffableDataSource

@MainActor
final class PlaylistDetailDiffableDataSource: UITableViewDiffableDataSource<PlaylistDetailSection, PlaylistDetailItem> {
    let playlistID: UUID
    let store: PlaylistStore

    init(
        tableView: UITableView,
        playlistID: UUID,
        store: PlaylistStore,
        cellProvider: @escaping UITableViewDiffableDataSource<PlaylistDetailSection, PlaylistDetailItem>.CellProvider,
    ) {
        self.playlistID = playlistID
        self.store = store
        super.init(tableView: tableView, cellProvider: cellProvider)
    }

    override func tableView(_: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        guard let item = itemIdentifier(for: indexPath) else { return false }
        if case .song = item { return true }
        return false
    }

    override func tableView(_: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        guard let item = itemIdentifier(for: indexPath) else { return false }
        if case .song = item { return true }
        return false
    }

    override func tableView(
        _: UITableView,
        moveRowAt sourceIndexPath: IndexPath,
        to destinationIndexPath: IndexPath,
    ) {
        guard let sourceItem = itemIdentifier(for: sourceIndexPath),
              case .song = sourceItem
        else { return }

        let tracksSnapshot = snapshot().itemIdentifiers(inSection: .tracks)
        guard let sourceTrackIndex = tracksSnapshot.firstIndex(of: sourceItem) else { return }

        let destTrackIndex: Int = if let destItem = itemIdentifier(for: destinationIndexPath),
                                     let idx = tracksSnapshot.firstIndex(of: destItem)
        {
            idx
        } else {
            max(tracksSnapshot.count - 1, 0)
        }

        AppLog.info("PlaylistDetailViewController", "moveSong from=\(sourceTrackIndex) to=\(destTrackIndex) playlistID=\(playlistID)")
        store.moveSong(in: playlistID, from: sourceTrackIndex, to: destTrackIndex)
    }

    override func tableView(
        _: UITableView,
        commit editingStyle: UITableViewCell.EditingStyle,
        forRowAt indexPath: IndexPath,
    ) {
        guard editingStyle == .delete,
              let item = itemIdentifier(for: indexPath),
              case let .song(entryID, _) = item,
              let songs = store.playlist(for: playlistID)?.songs,
              let songIndex = songs.firstIndex(where: { $0.entryID == entryID })
        else { return }

        let song = songs[songIndex]
        AppLog.info("PlaylistDetailViewController", "removeSong index=\(songIndex) trackID=\(song.trackID) name=\(song.title) from playlistID=\(playlistID)")
        store.removeSong(at: songIndex, from: playlistID)

        var snapshot = snapshot()
        snapshot.deleteItems([item])
        apply(snapshot, animatingDifferences: true)
    }
}

// MARK: - UIImagePickerControllerDelegate

extension PlaylistDetailViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any],
    ) {
        picker.dismiss(animated: true)
        let image = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage)
        guard let image else {
            return
        }

        let maxSize: CGFloat = 600
        let scale = min(maxSize / image.size.width, maxSize / image.size.height, 1)
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }

        let data = resized.jpegData(compressionQuality: 0.8)
        store.updateCover(id: playlistID, imageData: data)
        populateHeader()
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
}
