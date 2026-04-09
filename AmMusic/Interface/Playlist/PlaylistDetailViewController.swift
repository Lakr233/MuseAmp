import AlertController
import AmMusicDatabaseKit
import Then
import UIKit

@MainActor
final class PlaylistDetailViewController: MediaDetailViewController, UITableViewDataSource, UITableViewDelegate, UITableViewDragDelegate {
    let playlistID: UUID
    let store: PlaylistStore
    let environment: AppEnvironment?

    private var playlistsDidChangeObserver: NSObjectProtocol?

    var playlist: Playlist? {
        store.playlist(for: playlistID)
    }

    var headerCoverTask: Task<Void, Never>?
    var localArtworkPrefetchTask: Task<Void, Never>?
    lazy var playlistMenuProvider = AddToPlaylistMenuProvider(
        playlistStore: store,
        viewController: self
    )
    lazy var playbackMenuProvider = environment.map {
        PlaybackMenuProvider(playbackController: $0.playbackController)
    }

    lazy var songExportPresenter = SongExportPresenter(
        viewController: self,
        lyricsStore: environment?.lyricsCacheStore,
        locations: environment?.paths,
        apiClient: environment?.apiClient
    )
    lazy var songContextMenuProvider = SongContextMenuProvider(
        playlistMenuProvider: playlistMenuProvider,
        exportPresenter: songExportPresenter
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

        configureDetailArtwork(placeholder: "music.note.list")
        updateOptionsMenu()
        configureHeader()
        configureTableView()
        populateHeader()
        observePlaylistChanges()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLibraryDidSync),
            name: .libraryDidSync,
            object: nil
        )
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
            queue: .main
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
        tableView.reloadData()
        prefetchLocalArtworkIfNeeded()
        updateOptionsMenu()
    }

    // MARK: - Header

    private func configureHeader() {
        configureDetailHeader(
            arrangedSubviews: [],
            artworkSize: 200,
            customSpacings: []
        )
    }

    func populateHeader() {
        guard let playlist else {
            updateFooter()
            invalidateHeaderLayout()
            return
        }
        title = playlist.name
        updateFooter()
        invalidateHeaderLayout()

        headerCoverTask?.cancel()
        if let coverData = playlist.coverImageData, let image = UIImage(data: coverData) {
            AppLog.verbose(self, "populateHeader playlistID=\(playlist.id) using custom cover bytes=\(coverData.count)")
            artworkImageView.setImage(image)
            return
        }

        guard !playlist.songs.isEmpty else {
            AppLog.verbose(self, "populateHeader playlistID=\(playlist.id) no songs reset artwork")
            artworkImageView.reset()
            return
        }

        AppLog.verbose(self, "populateHeader playlistID=\(playlist.id) generating artwork")
        artworkImageView.reset()
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
                    "header cover task dropped playlistID=\(playlist.id) current=\(playlistID.uuidString)"
                )
                return
            }
            AppLog.verbose(self, "header cover task applied playlistID=\(playlist.id)")
            artworkImageView.setImage(image)
        }
    }

    // MARK: - Table View

    private func configureTableView() {
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(AmSongCell.self, forCellReuseIdentifier: AmSongCell.reuseID)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 64
        tableView.separatorInset = .zero
        tableView.layoutMargins = .zero
        tableView.cellLayoutMarginsFollowReadableWidth = false
        tableView.insetsContentViewsToSafeArea = false
        tableView.sectionHeaderTopPadding = 0

        tableView.dragInteractionEnabled = true
        tableView.dragDelegate = self

        configureDetailTableView(backgroundColor: .systemBackground)
        configureDetailFooter(hidden: true)
    }

    private func updateFooter() {
        guard let playlist else {
            updateFooterText(nil)
            return
        }

        let songCount = playlist.songs.count
        guard songCount > 0 else {
            updateFooterText(nil)
            return
        }

        let totalMillis = playlist.songs.compactMap(\.durationMillis).reduce(0, +)
        let songCountText = songCount == 1 ? String(localized: "1 song") : String(localized: "\(songCount) songs")

        if totalMillis > 0 {
            let minutes = totalMillis / 1000 / 60
            updateFooterText(String(localized: "\(songCountText), \(minutes) minutes"))
        } else {
            updateFooterText(songCountText)
        }
    }

    // MARK: - UITableViewDataSource

    func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
        playlist?.songs.count ?? 0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: AmSongCell.reuseID,
            for: indexPath
        ) as! AmSongCell
        guard let songs = playlist?.songs, songs.indices.contains(indexPath.row) else {
            return cell
        }
        let song = songs[indexPath.row]

        cell.configure(with: song, artworkURL: artworkURL(for: song))
        cell.setDownloadedIndicatorVisible(isSongDownloaded(song))
        cell.separatorInset = .zero
        cell.layoutMargins = .zero

        return cell
    }

    func tableView(
        _: UITableView,
        commit editingStyle: UITableViewCell.EditingStyle,
        forRowAt indexPath: IndexPath
    ) {
        guard editingStyle == .delete else {
            return
        }
        guard let songs = playlist?.songs, songs.indices.contains(indexPath.row) else {
            AppLog.warning(self, "commit delete missing song index=\(indexPath.row) playlistID=\(playlistID)")
            return
        }
        let song = songs[indexPath.row]
        AppLog.info(self, "removeSong index=\(indexPath.row) trackID=\(song.trackID) name=\(song.title) from playlistID=\(playlistID)")
        store.removeSong(at: indexPath.row, from: playlistID)
        tableView.deleteRows(at: [indexPath], with: .automatic)
        populateHeader()
    }

    func tableView(_: UITableView, canMoveRowAt _: IndexPath) -> Bool {
        true
    }

    func tableView(_: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        AppLog.info(self, "moveSong from=\(sourceIndexPath.row) to=\(destinationIndexPath.row) playlistID=\(playlistID)")
        store.moveSong(in: playlistID, from: sourceIndexPath.row, to: destinationIndexPath.row)
    }

    // MARK: - UITableViewDelegate

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard environment != nil else {
            return
        }
        playSong(at: indexPath.row)
    }

    func tableView(
        _: UITableView,
        contextMenuConfigurationForRowAt indexPath: IndexPath,
        point _: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard let songs = playlist?.songs, songs.indices.contains(indexPath.row) else {
            return nil
        }
        let song = songs[indexPath.row]
        return UIContextMenuConfiguration(identifier: indexPath as NSIndexPath, previewProvider: nil) { [weak self] _ in
            guard let self else { return nil }
            let removeAction = UIAction(
                title: String(localized: "Remove"),
                image: UIImage(systemName: "minus.circle")
            ) { [weak self] _ in
                self?.confirmRemove(song: song)
            }

            var destructiveActions: [UIMenuElement] = [removeAction]
            if environment != nil {
                destructiveActions.append(UIAction(
                    title: String(localized: "Delete Song"),
                    image: UIImage(systemName: "trash"),
                    attributes: .destructive
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
                        }
                    ) ?? [],
                    destructiveActions: destructiveActions
                )
            )
        }
    }

    func tableView(
        _: UITableView,
        previewForHighlightingContextMenuWithConfiguration configuration: UIContextMenuConfiguration
    ) -> UITargetedPreview? {
        CellContextMenuPreviewHelper.targetedPreview(for: configuration, in: tableView)
    }

    func tableView(
        _: UITableView,
        previewForDismissingContextMenuWithConfiguration configuration: UIContextMenuConfiguration
    ) -> UITargetedPreview? {
        CellContextMenuPreviewHelper.targetedPreview(for: configuration, in: tableView)
    }

    // MARK: - UITableViewDragDelegate

    func tableView(_: UITableView, itemsForBeginning _: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
        guard let songs = playlist?.songs, songs.indices.contains(indexPath.row) else {
            return []
        }
        let song = songs[indexPath.row]
        guard let exportItem = exportItem(for: song) else {
            return []
        }

        let fileExtension = exportItem.sourceURL.pathExtension
        let fileName = fileExtension.isEmpty
            ? exportItem.preferredFileBaseName
            : "\(exportItem.preferredFileBaseName).\(fileExtension)"

        let provider = NSItemProvider()
        provider.suggestedName = fileName
        provider.registerFileRepresentation(
            forTypeIdentifier: "public.audio",
            fileOptions: [],
            visibility: .all
        ) { completion in
            completion(exportItem.sourceURL, false, nil)
            return nil
        }

        let dragItem = UIDragItem(itemProvider: provider)
        dragItem.localObject = song
        return [dragItem]
    }
}

// MARK: - UIImagePickerControllerDelegate

extension PlaylistDetailViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
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
