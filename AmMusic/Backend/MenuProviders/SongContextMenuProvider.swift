import AmMusicDatabaseKit
import UIKit

final class SongContextMenuProvider {
    enum Context {
        case album
        case downloads
        case library
        case playlist
        case search

        var allowsShowInAlbum: Bool {
            self != .album
        }
    }

    struct Configuration {
        var availablePlaylists: (() -> [Playlist])?
        var onAddToPlaylist: ((UUID) -> Void)?
        var showInAlbum: (() -> Void)?
        var exportItems: (() -> [SongExportItem])?
        var primaryActions: [UIMenuElement] = []
        var secondaryActions: [UIMenuElement] = []
        var destructiveActions: [UIMenuElement] = []
        var includesCopyMenu = true
    }

    private let playlistMenuProvider: AddToPlaylistMenuProvider?
    private let exportPresenter: SongExportPresenter?

    init(
        playlistMenuProvider: AddToPlaylistMenuProvider? = nil,
        exportPresenter: SongExportPresenter? = nil
    ) {
        self.playlistMenuProvider = playlistMenuProvider
        self.exportPresenter = exportPresenter
    }

    func menu(
        title: String? = nil,
        for song: PlaylistEntry,
        context: Context,
        configuration: Configuration = .init()
    ) -> UIMenu? {
        var sections: [UIMenuElement] = []

        if let primarySection = MenuSectionProvider.inline(configuration.primaryActions) {
            sections.append(primarySection)
        }

        var libraryActions: [UIMenuElement] = []

        if let playlistMenu = makeAddToPlaylistMenu(for: song, configuration: configuration) {
            libraryActions.append(playlistMenu)
        }

        if let exportAction = makeExportAction(configuration.exportItems) {
            libraryActions.append(exportAction)
        }

        if context.allowsShowInAlbum, let showInAlbum = configuration.showInAlbum {
            libraryActions.append(UIAction(
                title: String(localized: "Show in Album"),
                image: UIImage(systemName: "music.note.list")
            ) { _ in
                showInAlbum()
            })
        }

        if let librarySection = MenuSectionProvider.inline(libraryActions) {
            sections.append(librarySection)
        }

        if configuration.includesCopyMenu {
            var copyChildren: [UIMenuElement] = [makeCopyMenu(for: song)]
            copyChildren.append(makeInfoMenu(for: song))
            if let copySection = MenuSectionProvider.inline(copyChildren) {
                sections.append(copySection)
            }
        }

        if let secondarySection = MenuSectionProvider.inline(configuration.secondaryActions) {
            sections.append(secondarySection)
        }

        if let destructiveSection = MenuSectionProvider.inline(configuration.destructiveActions) {
            sections.append(destructiveSection)
        }

        guard !sections.isEmpty else {
            return nil
        }

        if let title {
            return UIMenu(title: title, children: sections)
        }
        return UIMenu(children: sections)
    }
}

private extension SongContextMenuProvider {
    func makeAddToPlaylistMenu(
        for song: PlaylistEntry,
        configuration: Configuration
    ) -> UIMenu? {
        guard let playlistMenuProvider,
              let availablePlaylists = configuration.availablePlaylists,
              !availablePlaylists().isEmpty
        else {
            return nil
        }

        return playlistMenuProvider.contextMenu(
            for: [song],
            playlistsProvider: availablePlaylists,
            onAdd: configuration.onAddToPlaylist
        )
    }

    func makeExportAction(_ exportItems: (() -> [SongExportItem])?) -> UIAction? {
        guard let exportItems,
              let exportPresenter
        else {
            return nil
        }

        return UIAction(
            title: String(localized: "Export"),
            image: UIImage(systemName: "square.and.arrow.up")
        ) { _ in
            let items = exportItems()
            guard !items.isEmpty else { return }
            exportPresenter.present(items: items)
        }
    }

    func makeInfoMenu(for song: PlaylistEntry) -> UIMenu {
        var children: [UIAction] = []

        if let albumID = song.albumID, !albumID.isEmpty {
            children.append(UIAction(
                title: "Album: \(albumID)",
                image: UIImage(systemName: "square.stack"),
                attributes: .disabled
            ) { _ in })
        }

        children.append(UIAction(
            title: "Song: \(song.trackID)",
            image: UIImage(systemName: "music.note"),
            attributes: .disabled
        ) { _ in })

        return UIMenu(
            title: String(localized: "Info"),
            image: UIImage(systemName: "info.circle"),
            children: children
        )
    }

    func makeCopyMenu(for song: PlaylistEntry) -> UIMenu {
        let copyName = UIAction(
            title: String(localized: "Song Name"),
            image: UIImage(systemName: "textformat")
        ) { _ in
            UIPasteboard.general.string = song.title
        }

        let copyArtist = UIAction(
            title: String(localized: "Artist Name"),
            image: UIImage(systemName: "person.text.rectangle")
        ) { _ in
            UIPasteboard.general.string = song.artistName
        }

        var children: [UIMenuElement] = [copyName, copyArtist]
        if let albumName = song.albumTitle, !albumName.isEmpty {
            children.append(UIAction(
                title: String(localized: "Album Name"),
                image: UIImage(systemName: "square.stack")
            ) { _ in
                UIPasteboard.general.string = albumName
            })
        }

        return CopyMenuProvider.menu(children: children)
    }
}
