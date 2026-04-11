//
//  PlaylistViewController+Editing.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import AlertController
import AmMusicDatabaseKit
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
            navigationItem.rightBarButtonItems = [makeDeleteSelectedButton()]
            return
        }

        navigationItem.leftBarButtonItem = nil
        navigationItem.rightBarButtonItems = [makeMenuButton(), addButton]
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

        let manageSection = UIMenu(options: .displayInline, children: [select])

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

    func makeDeleteSelectedButton() -> UIBarButtonItem {
        UIBarButtonItem(
            image: UIImage(systemName: "trash"),
            style: .plain,
            target: self,
            action: #selector(deleteSelectedTapped),
        ).then {
            $0.accessibilityIdentifier = "playlist.deleteSelected"
            $0.isEnabled = !selectedPlaylists().isEmpty
        }
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
        applySort()
        applyPlaylistsSnapshot(animated: true)
        updateNavigationItems()
    }
}
