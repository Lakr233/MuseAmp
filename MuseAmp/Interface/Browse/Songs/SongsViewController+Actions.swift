//
//  SongsViewController+Actions.swift
//  MuseAmp
//

import AlertController
import MuseAmpDatabaseKit
import UIKit

// MARK: - Selection Actions

extension SongsViewController {
    @objc func selectTapped() {
        setEditing(true, animated: true)
    }

    @objc func finishSelectionTapped() {
        setEditing(false, animated: true)
    }

    func selectedTracks() -> [AudioTrackRecord] {
        guard let selectedRows = tableView.indexPathsForSelectedRows else {
            return []
        }
        return selectedRows.compactMap { indexPath in
            guard let item = dataSource.itemIdentifier(for: indexPath),
                  case let .song(trackID) = item
            else { return nil }
            return tracksByID[trackID]
        }
    }

    func selectedPlaylistEntries() -> [PlaylistEntry] {
        selectedTracks().map { $0.playbackTrack(paths: environment.paths).playlistEntry }
    }

    @objc func deleteSelectedTapped() {
        let tracks = selectedTracks()
        guard !tracks.isEmpty else { return }

        let message = tracks.count == 1
            ? String(localized: "Delete \"\(tracks[0].title)\"? This cannot be undone.")
            : String(localized: "Delete \(tracks.count) songs? This cannot be undone.")

        ConfirmationAlertPresenter.present(
            on: self,
            title: String(localized: "Delete Songs"),
            message: message,
            confirmTitle: String(localized: "Delete"),
        ) { [weak self] in
            guard let self else { return }
            environment.musicLibraryTrackRemovalService.removeTracks(tracks)
            environment.playbackController.removeTracksFromQueue(trackIDs: Set(tracks.map(\.trackID)))
            reloadTracks()
            setEditing(false, animated: true)
        }
    }

    func exportSelectedSongs() {
        let items = selectedTracks().map { exportItem(for: $0) }
        guard !items.isEmpty else { return }
        songExportPresenter.present(items: items, barButtonItem: navigationItem.rightBarButtonItem)
    }

    func copySelectedSongNames() {
        UIPasteboard.general.string = selectedTracks().map(\.title).joined(separator: "\n")
    }

    func copySelectedArtistNames() {
        UIPasteboard.general.string = selectedTracks().map(\.artistName).joined(separator: "\n")
    }

    func createPlaylistFromSelection() {
        let entries = selectedPlaylistEntries()
        guard !entries.isEmpty else { return }

        let alert = AlertInputViewController(
            title: "New Playlist",
            message: "Enter a name for your playlist.",
            placeholder: "Playlist Name",
            text: "",
        ) { [weak self] name in
            guard let self else { return }
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                AppLog.warning(self, "createPlaylistFromSelection empty name after trim, ignoring")
                return
            }

            let playlist = environment.playlistStore.createPlaylist(name: trimmed)
            entries.forEach { self.environment.playlistStore.addSong($0, to: playlist.id) }
        }
        present(alert, animated: true)
    }
}

// MARK: - Editing Menu

extension SongsViewController {
    func buildEditingMenu() -> UIMenu {
        let selected = selectedTracks()
        if selected.isEmpty {
            return UIMenu(children: [buildSortMenu()])
        }

        let addToPlaylistMenu = environment.playlistStore.playlists.isEmpty ? nil : playlistMenuProvider.menu(
            songsProvider: { [weak self] in
                self?.selectedPlaylistEntries() ?? []
            },
            title: String(localized: "Add to Playlist"),
            allowsCreatingPlaylist: false,
        )

        let createPlaylist = UIAction(
            title: String(localized: "New Playlist"),
            image: UIImage(systemName: "plus.rectangle.on.folder"),
        ) { [weak self] _ in
            self?.createPlaylistFromSelection()
        }

        let export = UIAction(
            title: String(localized: "Export Selected"),
            image: UIImage(systemName: "square.and.arrow.up"),
        ) { [weak self] _ in
            self?.exportSelectedSongs()
        }

        let copySongNames = UIAction(
            title: String(localized: "Song Names"),
            image: UIImage(systemName: "music.note.list"),
        ) { [weak self] _ in
            self?.copySelectedSongNames()
        }

        let copyArtists = UIAction(
            title: String(localized: "Artist Names"),
            image: UIImage(systemName: "person.text.rectangle"),
        ) { [weak self] _ in
            self?.copySelectedArtistNames()
        }

        let copy = UIMenu(
            title: String(localized: "Copy"),
            image: UIImage(systemName: "square.on.square"),
            children: [copySongNames, copyArtists],
        )

        let delete = UIAction(
            title: String(localized: "Delete Selected"),
            image: UIImage(systemName: "trash"),
            attributes: .destructive,
        ) { [weak self] _ in
            self?.deleteSelectedTapped()
        }

        var sections: [UIMenuElement] = [createPlaylist]
        if let addToPlaylistMenu {
            sections.insert(addToPlaylistMenu, at: 0)
        }
        sections.append(contentsOf: [export, copy, delete])
        return UIMenu(children: sections)
    }
}
