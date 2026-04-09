import AmMusicDatabaseKit
import UIKit

// MARK: - UITableViewDelegate

extension SongLibraryViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }

        if isEditing {
            updateNavigationItems()
            return
        }

        tableView.deselectRow(at: indexPath, animated: true)

        switch item {
        case let .album(id):
            guard let album = albumsByID[id] else { return }
            openAlbum(album)

        case let .track(trackID):
            guard let track = tracksByID[trackID] else { return }
            openAlbumForTrack(track)
        }
    }

    func tableView(_: UITableView, didDeselectRowAt _: IndexPath) {
        guard isEditing else { return }
        updateNavigationItems()
    }

    func tableView(_: UITableView, shouldBeginMultipleSelectionInteractionAt indexPath: IndexPath) -> Bool {
        guard !isSearchActive else { return false }
        return dataSource.itemIdentifier(for: indexPath) != nil
    }

    func tableView(_: UITableView, didBeginMultipleSelectionInteractionAt _: IndexPath) {
        setEditing(true, animated: true)
    }

    func tableViewDidEndMultipleSelectionInteraction(_: UITableView) {
        updateNavigationItems()
    }

    func tableView(
        _: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard !isEditing, !isSearchActive,
              let item = dataSource.itemIdentifier(for: indexPath),
              case let .album(id) = item,
              let album = albumsByID[id]
        else { return nil }

        let delete = UIContextualAction(style: .destructive, title: String(localized: "Delete")) { [weak self] _, _, completion in
            self?.deleteAlbum(album)
            completion(true)
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }

    func tableView(
        _: UITableView,
        contextMenuConfigurationForRowAt indexPath: IndexPath,
        point _: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard !isEditing,
              let item = dataSource.itemIdentifier(for: indexPath)
        else { return nil }

        switch item {
        case let .album(id):
            guard let album = albumsByID[id] else { return nil }
            return UIContextMenuConfiguration(identifier: indexPath as NSIndexPath, previewProvider: nil) { [weak self] _ in
                self?.buildMenu(for: album) ?? UIMenu()
            }

        case let .track(trackID):
            guard let track = tracksByID[trackID],
                  let album = albumsByID[track.albumID]
            else { return nil }
            return UIContextMenuConfiguration(identifier: indexPath as NSIndexPath, previewProvider: nil) { [weak self] _ in
                self?.buildMenu(for: album) ?? UIMenu()
            }
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
}

// MARK: - Album Navigation & Helpers

extension SongLibraryViewController {
    func buildMenu(for album: AlbumGroup) -> UIMenu {
        let openAlbumAction = UIAction(
            title: String(localized: "Open Album"),
            image: UIImage(systemName: "chevron.right")
        ) { [weak self] _ in
            self?.openAlbum(album)
        }

        let exportAction = UIAction(
            title: String(localized: "Export"),
            image: UIImage(systemName: "square.and.arrow.up")
        ) { [weak self] _ in
            guard let self else { return }
            let items = exportItems(for: album)
            guard !items.isEmpty else { return }
            songExportPresenter.present(items: items)
        }

        let songNames: [String]
        do {
            songNames = try environment.databaseManager.tracks(inAlbumID: album.albumID).map(\.title)
        } catch {
            AppLog.error(self, "buildMenu tracks query failed albumID=\(album.albumID) error=\(error)")
            songNames = []
        }
        let copyMenu = CopyMenuProvider.albumMenu(
            albumName: album.albumTitle,
            artistName: album.artistName,
            songNames: songNames
        )

        let deleteAction = UIAction(
            title: String(localized: "Delete Album"),
            image: UIImage(systemName: "trash"),
            attributes: .destructive
        ) { [weak self] _ in
            guard let self, let album = albumsByID[album.id] else { return }
            deleteAlbum(album)
        }

        var sections: [UIMenuElement] = []
        if let playbackSection = MenuSectionProvider.inline(
            playbackMenuProvider.listPrimaryActions(
                tracksProvider: { [weak self] in
                    self?.playbackTracks(for: album) ?? []
                },
                sourceProvider: { .album(id: album.id) }
            )
        ) {
            sections.append(playbackSection)
        }
        if let openSection = MenuSectionProvider.inline([openAlbumAction, exportAction]) {
            sections.append(openSection)
        }
        sections.append(UIMenu(options: .displayInline, children: [copyMenu]))
        sections.append(UIMenu(options: .displayInline, children: [deleteAction]))
        return UIMenu(children: sections)
    }

    func openAlbum(_ album: AlbumGroup) {
        albumNavigationHelper.pushAlbumDetail(album: localCatalogAlbum(from: album))
    }

    func openAlbumForTrack(_ track: AudioTrackRecord) {
        guard let album = albumsByID[track.albumID] else {
            AppLog.warning(self, "openAlbumForTrack: no album found for trackID=\(track.trackID)")
            return
        }
        albumNavigationHelper.pushAlbumDetail(
            album: localCatalogAlbum(from: album),
            highlightSongs: [track.trackID]
        )
    }

    func playbackTracksForVisibleList() -> [PlaybackTrack] {
        albums.flatMap(playbackTracks(for:))
    }

    func playbackTracks(for album: AlbumGroup) -> [PlaybackTrack] {
        do {
            let tracks = try environment.databaseManager.tracks(inAlbumID: album.albumID)
            return tracks.map { $0.playbackTrack(paths: environment.paths) }
        } catch {
            AppLog.error(self, "playbackTracks query failed albumID=\(album.albumID) error=\(error)")
            return []
        }
    }

    func albumSubtitle(for album: AlbumGroup) -> String {
        let songSummary = album.trackCount == 1
            ? String(localized: "1 song")
            : String(localized: "\(album.trackCount) songs")
        let durationMinutes = Int((album.totalDurationSeconds / 60).rounded())

        var subtitleParts = [album.artistName, songSummary]
        if durationMinutes > 0 {
            subtitleParts.append(String(localized: "\(durationMinutes) min"))
        }
        return subtitleParts.joined(separator: " · ")
    }

    func localCatalogAlbum(from album: AlbumGroup) -> CatalogAlbum {
        let tracks: [AudioTrackRecord]
        do {
            tracks = try environment.databaseManager.tracks(inAlbumID: album.albumID)
        } catch {
            AppLog.error(self, "localCatalogAlbum tracks query failed albumID=\(album.albumID) error=\(error)")
            tracks = []
        }
        let firstTrack = tracks.first
        let artworkTrackID = album.artworkTrackID ?? firstTrack?.trackID
        let artwork: Artwork? = artworkTrackID.flatMap { cachedArtwork(forTrackID: $0) }
        let attributes = CatalogAlbumAttributes(
            artistName: album.artistName,
            name: album.albumTitle,
            trackCount: album.trackCount,
            releaseDate: firstTrack?.releaseDate,
            genreNames: firstTrack?.genreName.map { [$0] },
            artwork: artwork
        )
        let relationships = CatalogAlbumRelationships(
            tracks: ResourceList(
                href: nil,
                next: nil,
                data: tracks.map { $0.catalogSong(artwork: cachedArtwork(forTrackID: $0.trackID)) }
            )
        )
        return CatalogAlbum(
            id: album.id,
            type: "albums",
            href: nil,
            attributes: attributes,
            relationships: relationships
        )
    }

    func cachedArtwork(forTrackID trackID: String) -> Artwork? {
        let artworkURL = environment.paths.artworkCacheURL(for: trackID)
        guard FileManager.default.fileExists(atPath: artworkURL.path) else {
            return nil
        }
        return Artwork(width: nil, height: nil, url: artworkURL.absoluteString)
    }
}
