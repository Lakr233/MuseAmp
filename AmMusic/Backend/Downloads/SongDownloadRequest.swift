import Foundation

nonisolated struct SongDownloadRequest {
    let trackID: String
    let albumID: String
    let title: String
    let artistName: String
    let albumName: String?
    let artworkURL: URL?
}
