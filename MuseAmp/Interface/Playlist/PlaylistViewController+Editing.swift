//
//  PlaylistViewController+Editing.swift
//  MuseAmp
//
//  Created by @Lakr233 on 2026/04/11.
//

import AlertController
import MuseAmpDatabaseKit
import Then
import UIKit

// MARK: - Editing

extension PlaylistViewController {
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
            return
        }

        navigationItem.leftBarButtonItem = nil
        navigationItem.rightBarButtonItems = [makeMenuButton(), addButton]
    }

    func buildEditingMenu() -> UIMenu {
        let selected = selectedPlaylists()
        if selected.isEmpty {
            return UIMenu(children: [buildSortMenu()])
        }

        let selectedIDs = Set(selected.map(\.id))
        let addToPlaylist: UIMenu? = {
            let candidates = store.playlists.filter { !selectedIDs.contains($0.id) }
            guard !candidates.isEmpty else { return nil }
            return addToPlaylistMenuProvider.menu(
                songsProvider: { [weak self] in
                    self?.selectedPlaylistSongs() ?? []
                },
                playlistsProvider: { candidates },
                title: String(localized: "Add to Playlist"),
                allowsCreatingPlaylist: false,
            )
        }()

        let createPlaylist = UIAction(
            title: String(localized: "New Playlist"),
            image: UIImage(systemName: "plus.rectangle.on.folder"),
        ) { [weak self] _ in
            self?.createPlaylistFromSelection()
        }

        let delete = UIAction(
            title: String(localized: "Delete Selected"),
            image: UIImage(systemName: "trash"),
            attributes: .destructive,
        ) { [weak self] _ in
            self?.deleteSelectedTapped()
        }

        var sections: [UIMenuElement] = [createPlaylist]
        if let addToPlaylist {
            sections.insert(addToPlaylist, at: 0)
        }
        sections.append(delete)
        return UIMenu(children: sections)
    }

    func selectedPlaylistSongs() -> [PlaylistEntry] {
        selectedPlaylists().flatMap(\.songs)
    }

    func createPlaylistFromSelection() {
        let entries = selectedPlaylistSongs()
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

            let playlist = store.createPlaylist(name: trimmed)
            entries.forEach { self.store.addSong($0, to: playlist.id) }
            reloadPlaylists()
        }
        present(alert, animated: true)
    }

    func makeMenuButton() -> UIBarButtonItem {
        UIBarButtonItem(
            image: UIImage(systemName: "ellipsis.circle"),
            menu: buildPlaylistMenu(),
        ).then {
            $0.accessibilityLabel = String(localized: "Playlist Actions")
        }
    }

    func buildPlaylistMenu() -> UIMenu {
        let select = UIAction(
            title: String(localized: "Select"),
            image: UIImage(systemName: "checkmark.circle"),
        ) { [weak self] _ in
            self?.selectTapped()
        }

        var manageActions: [UIMenuElement] = [select]
        if environment != nil {
            manageActions.append(UIAction(
                title: String(localized: "Import Playlist"),
                image: UIImage(systemName: "square.and.arrow.down"),
            ) { [weak self] _ in
                self?.playlistTransferCoordinator.presentImportPicker()
            })
        }

        let manageSection = UIMenu(options: .displayInline, children: manageActions)

        return UIMenu(children: [buildSortMenu(), manageSection])
    }

    func buildSortMenu() -> UIMenu {
        let sortMenu = UIMenu(
            title: String(localized: "Sort By"),
            image: UIImage(systemName: "arrow.up.arrow.down"),
            children: SortOption.allCases.map { option in
                UIAction(
                    title: option.title,
                    image: UIImage(systemName: option.imageName),
                    state: sortOption == option ? .on : .off,
                ) { [weak self] _ in
                    self?.sortPlaylists(by: option)
                }
            },
        )
        return UIMenu(options: .displayInline, children: [sortMenu])
    }

    @objc func selectTapped() {
        setEditing(true, animated: true)
    }

    @objc func finishSelectionTapped() {
        setEditing(false, animated: true)
    }

    @objc func deleteSelectedTapped() {
        let playlists = selectedPlaylists()
        guard !playlists.isEmpty else { return }
        presentDeleteAlert(for: playlists) { [weak self] in
            self?.store.deletePlaylists(ids: playlists.map(\.id))
            self?.setEditing(false, animated: true)
            self?.reloadPlaylists()
        }
    }

    func selectedPlaylists() -> [Playlist] {
        guard let selectedRows = tableView.indexPathsForSelectedRows else { return [] }
        return selectedRows.compactMap { indexPath in
            guard let item = dataSource.itemIdentifier(for: indexPath),
                  case let .playlist(id) = item
            else { return nil }
            return playlistsByID[id]
        }
    }

    func presentDeleteAlert(for playlists: [Playlist], onDelete: @escaping () -> Void) {
        let isSingle = playlists.count == 1
        let title = isSingle ? String(localized: "Delete Playlist") : String(localized: "Delete Playlists")
        let message = if isSingle {
            String(localized: "Delete \"\(playlists[0].name)\"? This cannot be undone.")
        } else {
            String(localized: "Delete \(playlists.count) selected playlists? This cannot be undone.")
        }

        ConfirmationAlertPresenter.present(
            on: self,
            title: title,
            message: message,
            confirmTitle: isSingle ? String(localized: "Delete") : String(localized: "Delete Playlists"),
            onConfirm: onDelete,
        )
    }

    func sortPlaylists(by option: SortOption) {
        sortOption = option
        AppPreferences.setStoredSortOption(option, forKey: AppPreferences.playlistsSortOptionKey)
        applySort()
        applyPlaylistsSnapshot(animated: true)
        updateNavigationItems()
    }
}
