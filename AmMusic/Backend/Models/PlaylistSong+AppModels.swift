import AmMusicDatabaseKit
import Foundation

extension PlaylistEntry {
    nonisolated func downloadRequest(albumID: String, apiBaseURL: URL?) -> SongDownloadRequest {
        SongDownloadRequest(
            trackID: trackID,
            albumID: albumID,
            title: title,
            artistName: artistName,
            albumName: albumTitle,
            artworkURL: APIClient.resolveMediaURL(artworkURL, width: 600, height: 600, baseURL: apiBaseURL)
        )
    }
}
