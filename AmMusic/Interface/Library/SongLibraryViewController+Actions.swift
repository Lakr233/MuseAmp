import AlertController
import AmMusicDatabaseKit
import Then
import UIKit
import UniformTypeIdentifiers

// MARK: - Actions

extension SongLibraryViewController {
    @objc func selectTapped() {
        setEditing(true, animated: true)
    }

    @objc func finishSelectionTapped() {
        setEditing(false, animated: true)
    }

    @objc func importTapped() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.audio, .folder])
        picker.allowsMultipleSelection = true
        picker.delegate = self
        present(picker, animated: true)
    }

    func performImport(urls: [URL]) {
        let alert = AlertProgressIndicatorViewController(
            title: String(localized: "Importing"),
            message: String(localized: "Reading audio files...")
        )
        present(alert, animated: true)

        Task { [weak self, importer = environment.audioFileImporter] in
            let result = await importer.importFiles(urls: urls)

            await MainActor.run { [weak self] in
                alert.dismiss(animated: true) {
                    self?.showImportResult(result)
                }
            }
        }
    }

    func showImportResult(_ result: AudioImportResult) {
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
            message: lines.joined(separator: "\n")
        ) { context in
            context.addAction(title: String(localized: "OK"), attribute: .accent) {
                context.dispose()
            }
        }
        present(alert, animated: true)
    }

    func refreshLibrary() {
        ProgressActionPresenter.run(
            on: self,
            title: String(localized: "Refreshing Library"),
            message: String(localized: "Scanning saved songs..."),
            action: { [env = environment] in try await env.resyncSongLibrary() },
            completion: { [weak self] in self?.reloadAlbums() }
        )
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
                    menu: buildEditingMenu()
                ),
            ]
        } else {
            navigationItem.leftBarButtonItem = nil
            navigationItem.rightBarButtonItems = [
                UIBarButtonItem(
                    image: UIImage(systemName: "ellipsis.circle"),
                    menu: buildLibraryMenu()
                ).then {
                    $0.accessibilityLabel = String(localized: "Library Actions")
                },
                importButton,
            ]
        }
    }

    @objc func deleteSelectedTapped() {
        guard let selectedRows = tableView.indexPathsForSelectedRows, !selectedRows.isEmpty else { return }
        let albumsToDelete = selectedRows
            .compactMap { dataSource.itemIdentifier(for: $0) }
            .compactMap { (item: LibraryItem) -> AlbumGroup? in
                guard case let .album(id) = item else { return nil }
                return albumsByID[id]
            }
        deleteAlbums(albumsToDelete)
        reloadAlbums()
        setEditing(false, animated: true)
    }

    func deleteAlbum(_ album: AlbumGroup) {
        deleteAlbums([album])
        reloadAlbums()
    }

    func deleteAlbums(_ albumsToDelete: [AlbumGroup]) {
        var allTracks: [AudioTrackRecord] = []
        for album in albumsToDelete {
            do {
                let tracks = try environment.databaseManager.tracks(inAlbumID: album.albumID)
                allTracks.append(contentsOf: tracks)
            } catch {
                AppLog.error(self, "deleteAlbums tracks query failed albumID=\(album.albumID) error=\(error)")
            }
        }
        deleteTracks(allTracks)
    }

    func deleteTracks(_ tracksToDelete: [AudioTrackRecord]) {
        environment.musicLibraryTrackRemovalService.removeTracks(tracksToDelete)
        environment.playbackController.removeTracksFromQueue(trackIDs: Set(tracksToDelete.map(\.trackID)))
    }

    func selectedAlbums() -> [AlbumGroup] {
        guard let selectedRows = tableView.indexPathsForSelectedRows else {
            return []
        }
        return selectedRows.compactMap { indexPath in
            guard let item = dataSource.itemIdentifier(for: indexPath),
                  case let .album(id) = item
            else { return nil }
            return albumsByID[id]
        }
    }

    func sortAlbums(by option: SortOption) {
        sortOption = option
        applySort()
        albumsByID = Dictionary(uniqueKeysWithValues: albums.map { ($0.id, $0) })
        applyAlbumsSnapshot()
        updateNavigationItems()
    }

    func exportSelectedAlbums() {
        let items = selectedAlbums().flatMap(exportItems(for:))
        guard !items.isEmpty else { return }
        songExportPresenter.present(items: items, barButtonItem: navigationItem.rightBarButtonItem)
    }

    func exportItems(for album: AlbumGroup) -> [SongExportItem] {
        do {
            let tracks = try environment.databaseManager.tracks(inAlbumID: album.albumID)
            return tracks.map(exportItem(for:))
        } catch {
            AppLog.error(self, "exportItems tracks query failed albumID=\(album.albumID) error=\(error)")
            return []
        }
    }

    func copySelectedAlbumNames() {
        UIPasteboard.general.string = selectedAlbums().map(\.albumTitle).joined(separator: "\n")
    }

    func copySelectedAlbumArtists() {
        UIPasteboard.general.string = selectedAlbums().map(\.artistName).joined(separator: "\n")
    }

    func exportItem(for track: AudioTrackRecord) -> SongExportItem {
        track.exportItem(paths: environment.paths)
    }
}

// MARK: - Menu Builders

extension SongLibraryViewController {
    func buildEditingMenu() -> UIMenu {
        let selectedAlbums = selectedAlbums()
        if selectedAlbums.isEmpty {
            return UIMenu(title: String(localized: "Sort"), children: SortOption.allCases.map { option in
                UIAction(
                    title: option.title,
                    image: UIImage(systemName: option.imageName),
                    state: sortOption == option ? .on : .off
                ) { [weak self] _ in
                    self?.sortAlbums(by: option)
                }
            })
        }

        let export = UIAction(
            title: String(localized: "Export Selected"),
            image: UIImage(systemName: "square.and.arrow.up")
        ) { [weak self] _ in
            self?.exportSelectedAlbums()
        }

        let copyAlbumNames = UIAction(
            title: String(localized: "Album Names"),
            image: UIImage(systemName: "rectangle.stack")
        ) { [weak self] _ in
            self?.copySelectedAlbumNames()
        }

        let copyArtists = UIAction(
            title: String(localized: "Artist Names"),
            image: UIImage(systemName: "person.text.rectangle")
        ) { [weak self] _ in
            self?.copySelectedAlbumArtists()
        }

        let copy = UIMenu(
            title: String(localized: "Copy"),
            image: UIImage(systemName: "square.on.square"),
            children: [copyAlbumNames, copyArtists]
        )

        let delete = UIAction(
            title: String(localized: "Delete Selected"),
            image: UIImage(systemName: "trash"),
            attributes: .destructive
        ) { [weak self] _ in
            self?.deleteSelectedTapped()
        }

        return UIMenu(children: [export, copy, delete])
    }

    func buildSortMenu() -> UIMenu {
        let sortMenu = UIMenu(
            title: String(localized: "Sort By"),
            image: UIImage(systemName: "arrow.up.arrow.down"),
            children: SortOption.allCases.map { option in
                UIAction(
                    title: option.title,
                    image: UIImage(systemName: option.imageName),
                    state: sortOption == option ? .on : .off
                ) { [weak self] _ in
                    self?.sortAlbums(by: option)
                }
            }
        )
        return UIMenu(options: .displayInline, children: [sortMenu])
    }

    func buildLibraryMenu() -> UIMenu {
        var sections: [UIMenuElement] = []

        if let playbackSection = MenuSectionProvider.inline(
            playbackMenuProvider.listPrimaryActions(
                tracksProvider: { [weak self] in
                    self?.playbackTracksForVisibleList() ?? []
                },
                sourceProvider: { .library }
            )
        ) {
            sections.append(playbackSection)
        }

        sections.append(buildSortMenu())

        let select = UIAction(
            title: String(localized: "Select"),
            image: UIImage(systemName: "checkmark.circle")
        ) { [weak self] _ in
            self?.selectTapped()
        }

        let refresh = UIAction(
            title: String(localized: "Refresh"),
            image: UIImage(systemName: "arrow.clockwise")
        ) { [weak self] _ in
            self?.refreshLibrary()
        }

        if let manageSection = MenuSectionProvider.inline([select, refresh]) {
            sections.append(manageSection)
        }

        return UIMenu(children: sections)
    }
}

// MARK: - UIDocumentPickerDelegate

extension SongLibraryViewController: UIDocumentPickerDelegate {
    func documentPicker(_: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard !urls.isEmpty else { return }
        performImport(urls: urls)
    }
}
