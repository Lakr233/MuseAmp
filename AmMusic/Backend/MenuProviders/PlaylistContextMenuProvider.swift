//
//  PlaylistContextMenuProvider.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import AlertController
import AmMusicDatabaseKit
import UIKit

final class PlaylistContextMenuProvider {
    private let playlistStore: PlaylistStore
    private weak var viewController: UIViewController?

    init(playlistStore: PlaylistStore, viewController: UIViewController? = nil) {
        self.playlistStore = playlistStore
        self.viewController = viewController
    }

    func menu(
        playlistProvider: @escaping () -> Playlist?,
        includesOpenAction: Bool = true,
        onOpen: ((Playlist) -> Void)? = nil,
        onRename: ((Playlist) -> Void)? = nil,
        onDuplicate: ((Playlist) -> Void)? = nil,
        onDelete: ((Playlist) -> Void)? = nil,
    ) -> UIMenu? {
        let deferred = UIDeferredMenuElement.uncached { [weak self] completion in
            guard let self, let playlist = playlistProvider() else {
                completion([])
                return
            }

            let isLiked = playlist.isLikedSongsPlaylist

            var primaryActions: [UIMenuElement] = []

            if includesOpenAction, let onOpen {
                primaryActions.append(UIAction(
                    title: String(localized: "Open"),
                    image: UIImage(systemName: "arrow.right.circle"),
                ) { _ in
                    guard let playlist = playlistProvider() else { return }
                    onOpen(playlist)
                })
            }

            if !isLiked {
                primaryActions.append(UIAction(
                    title: String(localized: "Rename"),
                    image: UIImage(systemName: "pencil"),
                ) { [weak self] _ in
                    self?.presentRenameAlert(playlistProvider: playlistProvider, onRename: onRename)
                })
            }

            primaryActions.append(UIAction(
                title: String(localized: "Duplicate"),
                image: UIImage(systemName: "plus.square.on.square"),
            ) { [weak self] _ in
                guard let self, let playlist = playlistProvider() else { return }
                if let duplicated = playlistStore.duplicatePlaylist(id: playlist.id) {
                    onDuplicate?(duplicated)
                }
            })

            var sections: [UIMenuElement] = []
            if let primarySection = MenuSectionProvider.inline(primaryActions) {
                sections.append(primarySection)
            }

            let mergeTargets = playlistStore.playlists.filter { $0.id != playlist.id }
            if !playlist.songs.isEmpty, !mergeTargets.isEmpty {
                let mergeActions: [UIAction] = mergeTargets.map { target in
                    UIAction(
                        title: target.name,
                        image: UIImage(systemName: "music.note.list"),
                    ) { [weak self] _ in
                        guard let playlist = playlistProvider() else { return }
                        self?.playlistStore.mergeSongs(from: playlist.id, into: target.id)
                    }
                }
                let mergeMenu = UIMenu(
                    title: String(localized: "Merge Into…"),
                    image: UIImage(systemName: "arrow.triangle.merge"),
                    children: mergeActions,
                )
                if let mergeSection = MenuSectionProvider.inline([mergeMenu]) {
                    sections.append(mergeSection)
                }
            }

            if let copySection = MenuSectionProvider.inline([makeCopyMenu(for: playlist)]) {
                sections.append(copySection)
            }

            var destructiveActions: [UIMenuElement] = []

            if !playlist.songs.isEmpty {
                destructiveActions.append(UIAction(
                    title: String(localized: "Remove All Songs"),
                    image: UIImage(systemName: "xmark.circle"),
                    attributes: .destructive,
                ) { [weak self] _ in
                    self?.presentClearSongsAlert(playlistProvider: playlistProvider)
                })
            }

            if !isLiked {
                destructiveActions.append(UIAction(
                    title: String(localized: "Delete"),
                    image: UIImage(systemName: "trash"),
                    attributes: .destructive,
                ) { [weak self] _ in
                    self?.presentDeleteAlert(playlistProvider: playlistProvider, onDelete: onDelete)
                })
            }

            if !destructiveActions.isEmpty,
               let destructiveSection = MenuSectionProvider.inline(destructiveActions)
            {
                sections.append(destructiveSection)
            }

            completion(sections)
        }

        return UIMenu(children: [deferred])
    }

    private func presentRenameAlert(
        playlistProvider: @escaping () -> Playlist?,
        onRename: ((Playlist) -> Void)?,
    ) {
        guard let viewController, let playlist = playlistProvider() else {
            return
        }

        let alert = AlertInputViewController(
            title: String(localized: "Rename Playlist"),
            message: String(localized: "Enter a new name for this playlist."),
            placeholder: String(localized: "Playlist Name"),
            text: playlist.name,
        ) { [weak self] name in
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return
            }

            self?.playlistStore.renamePlaylist(id: playlist.id, name: trimmed)
            guard let updatedPlaylist = self?.playlistStore.playlist(for: playlist.id) else {
                return
            }
            onRename?(updatedPlaylist)
        }
        viewController.present(alert, animated: true)
    }

    private func presentDeleteAlert(
        playlistProvider: @escaping () -> Playlist?,
        onDelete: ((Playlist) -> Void)?,
    ) {
        guard let viewController, let playlist = playlistProvider() else {
            return
        }

        ConfirmationAlertPresenter.present(
            on: viewController,
            title: String(localized: "Delete Playlist"),
            message: String(localized: "Delete \"\(playlist.name)\"? This cannot be undone."),
            confirmTitle: String(localized: "Delete"),
        ) { [weak self] in
            self?.playlistStore.deletePlaylist(id: playlist.id)
            onDelete?(playlist)
        }
    }

    private func presentClearSongsAlert(playlistProvider: @escaping () -> Playlist?) {
        guard let viewController, let playlist = playlistProvider() else {
            return
        }

        ConfirmationAlertPresenter.present(
            on: viewController,
            title: String(localized: "Remove All Songs"),
            message: String(localized: "Remove all songs from \"\(playlist.name)\"? This cannot be undone."),
            confirmTitle: String(localized: "Remove All"),
        ) { [weak self] in
            self?.playlistStore.clearSongs(in: playlist.id)
        }
    }

    private func makeCopyMenu(for playlist: Playlist) -> UIMenu {
        var children: [UIMenuElement] = [
            UIAction(
                title: String(localized: "Playlist Name"),
                subtitle: playlist.name,
                image: UIImage(systemName: "textformat"),
            ) { _ in
                UIPasteboard.general.string = playlist.name
            },
        ]

        if !playlist.songs.isEmpty {
            children.append(UIAction(
                title: String(localized: "All Song Names"),
                subtitle: playlist.songs.first?.title,
                image: UIImage(systemName: "music.note.list"),
            ) { _ in
                UIPasteboard.general.string = playlist.songs.map(\.title).joined(separator: "\n")
            })
        }

        return CopyMenuProvider.menu(children: children)
    }
}
