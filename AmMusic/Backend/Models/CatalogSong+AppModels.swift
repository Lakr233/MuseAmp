import AmMusicDatabaseKit
import AmMusicKit
import Foundation

extension CatalogSong {
    func playlistEntry(
        albumID: String? = nil,
        albumName: String? = nil
    ) -> PlaylistEntry {
        PlaylistEntry(
            trackID: id,
            title: attributes.name,
            artistName: attributes.artistName,
            albumID: albumID ?? relationships?.albums?.data.first?.id,
            albumTitle: albumName ?? attributes.albumName,
            artworkURL: attributes.artwork?.url,
            durationMillis: attributes.durationInMillis,
            trackNumber: attributes.trackNumber
        )
    }

    func downloadRequest(
        albumID: String,
        apiClient: APIClient,
        artworkWidth: Int = 600,
        artworkHeight: Int = 600
    ) -> SongDownloadRequest {
        SongDownloadRequest(
            trackID: id,
            albumID: albumID,
            title: attributes.name,
            artistName: attributes.artistName,
            albumName: attributes.albumName,
            artworkURL: apiClient.mediaURL(
                from: attributes.artwork?.url,
                width: artworkWidth,
                height: artworkHeight
            )
        )
    }
}
