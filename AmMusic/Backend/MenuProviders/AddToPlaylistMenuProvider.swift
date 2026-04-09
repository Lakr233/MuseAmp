import AlertController
import AmMusicDatabaseKit
import UIKit

final class AddToPlaylistMenuProvider {
    private let playlistStore: PlaylistStore
    private weak var viewController: UIViewController?

    init(playlistStore: PlaylistStore, viewController: UIViewController? = nil) {
        self.playlistStore = playlistStore
        self.viewController = viewController
    }

    func menu(
        for songs: [PlaylistEntry],
        title: String = String(localized: "Add to Playlist"),
        newPlaylistTitle: String = String(localized: "New Playlist…"),
        allowsCreatingPlaylist: Bool = true,
        onAdd: ((UUID) -> Void)? = nil
    ) -> UIMenu {
        menu(
            songsProvider: { songs },
            playlistsProvider: { self.playlistStore.playlists },
            title: title,
            newPlaylistTitle: newPlaylistTitle,
            allowsCreatingPlaylist: allowsCreatingPlaylist,
            onAdd: onAdd
        )
    }

    func contextMenu(
        for songs: [PlaylistEntry],
        playlistsProvider: (() -> [Playlist])? = nil,
        title: String = String(localized: "Add to Playlist"),
        onAdd: ((UUID) -> Void)? = nil
    ) -> UIMenu {
        contextMenu(
            songsProvider: { songs },
            playlistsProvider: playlistsProvider,
            title: title,
            onAdd: onAdd
        )
    }

    func contextMenu(
        songsProvider: @escaping () -> [PlaylistEntry],
        playlistsProvider: (() -> [Playlist])? = nil,
        title: String = String(localized: "Add to Playlist"),
        onAdd: ((UUID) -> Void)? = nil
    ) -> UIMenu {
        menu(
            songsProvider: songsProvider,
            playlistsProvider: playlistsProvider ?? { self.playlistStore.playlists },
            title: title,
            newPlaylistTitle: "",
            allowsCreatingPlaylist: false,
            onAdd: onAdd
        )
    }

    func menu(
        songsProvider: @escaping () -> [PlaylistEntry],
        playlistsProvider: (() -> [Playlist])? = nil,
        title: String = String(localized: "Add to Playlist"),
        newPlaylistTitle: String = String(localized: "New Playlist…"),
        allowsCreatingPlaylist: Bool = true,
        onAdd: ((UUID) -> Void)? = nil
    ) -> UIMenu {
        let deferred = UIDeferredMenuElement.uncached { [weak self] completion in
            guard let self else {
                completion([])
                return
            }

            let playlists = playlistsProvider?() ?? playlistStore.playlists
            let playlistActions: [UIMenuElement] = playlists.map { playlist in
                UIAction(title: playlist.name, image: UIImage(systemName: "music.note.list")) { [weak self] _ in
                    let addedIDs = songsProvider().compactMap { song -> UUID? in
                        self?.playlistStore.addSong(song, to: playlist.id) == true ? playlist.id : nil
                    }
                    if let first = addedIDs.first {
                        onAdd?(first)
                    }
                }
            }

            var sections: [UIMenuElement] = []
            if let playlistSection = MenuSectionProvider.inline(playlistActions) {
                sections.append(playlistSection)
            }

            if allowsCreatingPlaylist {
                let newPlaylistAction = UIAction(
                    title: newPlaylistTitle,
                    image: UIImage(systemName: "plus")
                ) { [weak self] _ in
                    self?.presentCreatePlaylistAlert { playlistID in
                        let addedIDs = songsProvider().compactMap { song -> UUID? in
                            self?.playlistStore.addSong(song, to: playlistID) == true ? playlistID : nil
                        }
                        if let first = addedIDs.first {
                            onAdd?(first)
                        }
                    }
                }

                if let createSection = MenuSectionProvider.inline([newPlaylistAction]) {
                    sections.append(createSection)
                }
            }

            completion(sections)
        }

        return UIMenu(
            title: title,
            image: UIImage(systemName: "text.badge.plus"),
            children: [deferred]
        )
    }

    private func presentCreatePlaylistAlert(then handler: @escaping (UUID) -> Void) {
        guard let viewController else {
            return
        }
        let alert = AlertInputViewController(
            title: String(localized: "New Playlist"),
            message: String(localized: "Enter a name for your playlist."),
            placeholder: String(localized: "Playlist Name"),
            text: ""
        ) { [weak self] name in
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return
            }
            let playlist = self?.playlistStore.createPlaylist(name: trimmed)
            if let playlist {
                handler(playlist.id)
            } else {
                AppLog.error(self ?? AddToPlaylistMenuProvider.self, "presentCreatePlaylistAlert createPlaylist returned nil")
            }
        }
        viewController.present(alert, animated: true)
    }
}
