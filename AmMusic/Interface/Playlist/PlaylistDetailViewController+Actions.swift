import AlertController
import AmMusicDatabaseKit
import UIKit

extension PlaylistDetailViewController {
    func showRenameAlert() {
        let alert = AlertInputViewController(
            title: String(localized: "Rename Playlist"),
            message: String(localized: "Enter a new name for this playlist."),
            placeholder: String(localized: "Playlist Name"),
            text: playlist?.name ?? ""
        ) { [weak self] name in
            guard let self else { return }
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return
            }
            store.renamePlaylist(id: playlistID, name: trimmed)
            title = trimmed
        }
        present(alert, animated: true)
    }

    func showImagePicker() {
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.allowsEditing = true
        picker.delegate = self
        present(picker, animated: true)
    }

    func refreshPlaylistSongs() {
        guard let environment else { return }
        guard let playlist, !playlist.songs.isEmpty else { return }

        let progress = AlertProgressIndicatorViewController(
            title: String(localized: "Refreshing"),
            message: String(localized: "Fetching latest song data...")
        )
        present(progress, animated: true)

        Task { @MainActor [weak self] in
            guard let self else { return }
            let updated = await store.refreshSongs(in: playlistID, using: environment.apiClient)
            progress.dismiss(animated: true) { [weak self] in
                guard let self else { return }
                refreshDownloadStateUI()
                AppLog.info(self, "refreshPlaylistSongs completed playlistID=\(playlistID) updated=\(updated)")
            }
        }
    }

    func downloadAllSongs() async {
        guard let environment, let playlist else {
            AppLog.warning(self, "downloadAllSongs missing environment or playlist playlistID=\(playlistID)")
            return
        }

        let requests = await withTaskGroup(of: SongDownloadRequest.self) { group in
            for entry in playlist.songs {
                group.addTask {
                    let albumID = await self.resolvedAlbumID(for: entry, apiClient: environment.apiClient)
                    return entry.downloadRequest(
                        albumID: albumID ?? "unknown",
                        apiBaseURL: environment.apiClient.baseURL
                    )
                }
            }
            var results: [SongDownloadRequest] = []
            for await request in group {
                results.append(request)
            }
            return results
        }

        guard !requests.isEmpty else {
            AppLog.warning(self, "downloadAllSongs no requests to submit playlistID=\(playlistID)")
            return
        }
        let result = environment.downloadManager.submitRequests(requests)
        AppLog.info(self, "downloadAllSongs submit result queued=\(result.queued) skipped=\(result.skipped) playlistID=\(playlistID)")
        DownloadSubmissionFeedbackPresenter.present(result)
        updateOptionsMenu()
    }

    func playSong(at index: Int) {
        guard let environment,
              let playlist,
              playlist.songs.indices.contains(index),
              let track = playbackTrack(for: playlist.songs[index])
        else {
            return
        }
        Task { @MainActor in
            let count = await environment.playbackController.playNext([track])
            PlaybackFeedbackPresenter.presentPlayNextSuccess(count: count, tracks: [track])
        }
    }

    func playlistPlaybackTracks() -> [PlaybackTrack] {
        guard let playlist else {
            return []
        }
        let tracks = playlist.songs.compactMap { playbackTrack(for: $0) }
        if tracks.count != playlist.songs.count {
            AppLog.warning(
                self,
                "playlistPlaybackTracks dropped tracks expected=\(playlist.songs.count) actual=\(tracks.count) playlistID=\(playlistID)"
            )
        }
        return tracks
    }

    func availableTargetPlaylists(for entry: PlaylistEntry) -> [Playlist] {
        store.playlists.filter { playlist in
            playlist.id != playlistID && !playlist.songs.contains { $0.trackID == entry.trackID }
        }
    }

    func confirmRemove(song: PlaylistEntry) {
        presentConfirmationAlert(
            title: String(localized: "Remove Song"),
            message: String(localized: "Remove \"\(song.title)\" from this playlist?"),
            confirmTitle: String(localized: "Remove")
        ) { [weak self] in
            self?.removeSongFromPlaylist(song)
        }
    }

    func confirmDeleteSong(_ song: PlaylistEntry) {
        presentConfirmationAlert(
            title: String(localized: "Delete Song"),
            message: String(localized: "Delete \"\(song.title)\" from your saved songs? This cannot be undone."),
            confirmTitle: String(localized: "Delete Song")
        ) { [weak self] in
            self?.deleteSong(song)
        }
    }

    func removeSongFromPlaylist(_ song: PlaylistEntry) {
        let currentSongs = playlist?.songs ?? []
        guard let currentIndex = currentSongs.firstIndex(where: { $0.entryID == song.entryID }) else {
            return
        }
        store.removeSong(at: currentIndex, from: playlistID)
        tableView.deleteRows(at: [IndexPath(row: currentIndex, section: 0)], with: .automatic)
        populateHeader()
    }

    func deleteSong(_ song: PlaylistEntry) {
        guard let environment else {
            return
        }

        environment.musicLibraryTrackRemovalService.removeTrack(trackID: song.trackID)
        environment.playbackController.removeTracksFromQueue(trackIDs: [song.trackID])
        removeSongFromPlaylist(song)
    }

    func exportItem(for entry: PlaylistEntry) -> SongExportItem? {
        guard let environment,
              let track = environment.libraryDatabase.trackOrNil(byID: entry.trackID)
        else {
            return nil
        }

        return track.exportItem(
            paths: environment.paths,
            displayArtist: entry.artistName,
            displayTitle: entry.title,
            displayAlbumName: entry.albumTitle,
            artworkURL: entry.artworkURL.flatMap { environment.apiClient.mediaURL(from: $0, width: 600, height: 600) }
        )
    }

    func openAlbum(for entry: PlaylistEntry) {
        guard let environment, let albumNavigationHelper else {
            return
        }

        if let track = environment.libraryDatabase.trackOrNil(byID: entry.trackID),
           track.albumID.isKnownAlbumID
        {
            let album = localCatalogAlbum(albumID: track.albumID, selectedTrack: track)
            albumNavigationHelper.pushAlbumDetail(album: album, highlightSongs: [entry.trackID])
            return
        }

        albumNavigationHelper.pushAlbumDetail(songID: entry.trackID, albumID: entry.albumID)
    }

    func isSongDownloaded(_ entry: PlaylistEntry) -> Bool {
        environment?.downloadStore.isDownloaded(trackID: entry.trackID) ?? false
    }

    func localCatalogAlbum(albumID: String, selectedTrack: AudioTrackRecord) -> CatalogAlbum {
        let albumTracks = localAlbumTracks(albumID: albumID)
            .sorted { lhs, rhs in
                if lhs.discNumber != rhs.discNumber {
                    return (lhs.discNumber ?? .max) < (rhs.discNumber ?? .max)
                }
                if lhs.trackNumber != rhs.trackNumber {
                    return (lhs.trackNumber ?? .max) < (rhs.trackNumber ?? .max)
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }

        let attributes = CatalogAlbumAttributes(
            artistName: selectedTrack.albumArtistName.nilIfEmpty ?? selectedTrack.artistName,
            name: selectedTrack.albumTitle.nilIfEmpty ?? selectedTrack.title,
            trackCount: albumTracks.count,
            releaseDate: selectedTrack.releaseDate,
            genreNames: selectedTrack.genreName.map { [$0] }
        )
        let relationships = CatalogAlbumRelationships(
            tracks: ResourceList(
                href: nil,
                next: nil,
                data: albumTracks.map { $0.catalogSong() }
            )
        )

        return CatalogAlbum(
            id: albumID,
            type: "albums",
            href: nil,
            attributes: attributes,
            relationships: relationships
        )
    }

    func localAlbumTracks(albumID: String) -> [AudioTrackRecord] {
        guard let environment else {
            return []
        }
        do {
            return try environment.databaseManager.tracks(inAlbumID: albumID)
        } catch {
            AppLog.error(self, "localAlbumTracks failed albumID=\(albumID) error=\(error)")
            return []
        }
    }

    func presentConfirmationAlert(
        title: String,
        message: String,
        confirmTitle: String,
        action: @escaping () -> Void
    ) {
        ConfirmationAlertPresenter.present(
            on: self,
            title: title,
            message: message,
            confirmTitle: confirmTitle,
            onConfirm: action
        )
    }

    func resolvedAlbumID(for entry: PlaylistEntry, apiClient: APIClient) async -> String? {
        if let albumID = entry.albumID, albumID.isKnownAlbumID {
            return albumID
        }
        guard let resolved = try? await apiClient.song(id: entry.trackID) else {
            return entry.albumID
        }
        let albumID = resolved.relationships?.albums?.data.first?.id
        return albumID.nilIfEmpty
    }

    func generatedCoverImage(for playlist: Playlist, sideLength: CGFloat) async -> UIImage? {
        guard let environment else { return nil }
        let apiBaseURL = environment.apiClient.baseURL
        return await environment.playlistCoverArtworkCache.image(
            for: playlist,
            sideLength: sideLength,
            scale: UIScreen.main.scale
        ) { rawURL, width, height in
            APIClient.resolveMediaURL(rawURL, width: width, height: height, baseURL: apiBaseURL)
        }
    }
}
