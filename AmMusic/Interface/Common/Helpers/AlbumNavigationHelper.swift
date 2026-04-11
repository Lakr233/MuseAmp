//
//  AlbumNavigationHelper.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import UIKit

@MainActor
final class AlbumNavigationHelper {
    private let environment: AppEnvironment
    private weak var viewController: UIViewController?

    init(environment: AppEnvironment, viewController: UIViewController?) {
        self.environment = environment
        self.viewController = viewController
    }

    func pushAlbumDetail(album: CatalogAlbum, highlightSongs: [String] = []) {
        let vc = AlbumDetailViewController(
            album: album,
            environment: environment,
            highlightSongs: highlightSongs,
        )
        push(vc)
    }

    func pushAlbumDetail(forCatalogSong song: CatalogSong) {
        if let album = song.relationships?.albums?.data.first {
            pushAlbumDetail(album: album, highlightSongs: [song.id])
            return
        }
        pushAlbumDetail(song: song)
    }

    func pushAlbumDetail(albumID: String, albumName: String = "", artistName: String = "", highlightSongs: [String] = []) {
        guard albumID.isKnownAlbumID else { return }
        let stub = CatalogAlbum(
            id: albumID,
            type: "albums",
            href: nil,
            attributes: CatalogAlbumAttributes(artistName: artistName, name: albumName),
            relationships: nil,
        )
        pushAlbumDetail(album: stub, highlightSongs: highlightSongs)
    }

    func pushAlbumDetail(songID: String, albumID: String?, albumName: String = "", artistName: String = "") {
        let vc = AlbumDetailViewController(
            songID: songID,
            albumID: albumID,
            albumName: albumName,
            artistName: artistName,
            environment: environment,
        )
        push(vc)
    }

    // MARK: - Private

    private func pushAlbumDetail(song: CatalogSong) {
        let vc = AlbumDetailViewController(song: song, environment: environment)
        push(vc)
    }

    private func push(_ vc: UIViewController) {
        viewController?.navigationController?.pushViewController(vc, animated: true)
    }
}
