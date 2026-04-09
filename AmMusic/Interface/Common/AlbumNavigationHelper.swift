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
            highlightSongs: highlightSongs
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

    func pushAlbumDetail(songID: String, albumID: String?) {
        Task { [weak self] in
            guard let self else { return }

            if let albumID, albumID.isKnownAlbumID,
               let album = try? await environment.apiClient.album(id: albumID)
            {
                pushAlbumDetail(album: album, highlightSongs: [songID])
                return
            }

            if let song = try? await environment.apiClient.song(id: songID) {
                pushAlbumDetail(forCatalogSong: song)
            }
        }
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
