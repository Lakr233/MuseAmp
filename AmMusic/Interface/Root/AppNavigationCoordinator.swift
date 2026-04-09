import UIKit

@MainActor
final class AppNavigationCoordinator {
    weak var rootViewController: UIViewController?
    let environment: AppEnvironment

    init(environment: AppEnvironment, rootViewController: UIViewController? = nil) {
        self.environment = environment
        self.rootViewController = rootViewController
    }

    // MARK: - Album Navigation

    func showAlbumDetail(_ album: CatalogAlbum, highlightSongs: [String] = []) {
        let vc = AlbumDetailViewController(
            album: album,
            environment: environment,
            highlightSongs: highlightSongs
        )
        push(vc)
    }

    func showAlbumDetail(forSong song: CatalogSong) {
        if let album = song.relationships?.albums?.data.first {
            showAlbumDetail(album, highlightSongs: [song.id])
            return
        }
        let vc = AlbumDetailViewController(song: song, environment: environment)
        push(vc)
    }

    func showAlbumDetail(songID: String, albumID: String?) {
        Task { [weak self] in
            guard let self else { return }

            if let albumID, albumID.isKnownAlbumID,
               let album = try? await environment.apiClient.album(id: albumID)
            {
                showAlbumDetail(album, highlightSongs: [songID])
                return
            }

            if let song = try? await environment.apiClient.song(id: songID) {
                showAlbumDetail(forSong: song)
            }
        }
    }

    // MARK: - Playlist Navigation

    func showPlaylistDetail(playlistID: UUID) {
        let vc = PlaylistDetailViewController(playlistID: playlistID, environment: environment)
        push(vc)
    }

    // MARK: - Private

    private func push(_ viewController: UIViewController) {
        navigationController?.pushViewController(viewController, animated: true)
    }

    private var navigationController: UINavigationController? {
        if let nav = rootViewController as? UINavigationController {
            return nav
        }
        return rootViewController?.navigationController
    }
}
