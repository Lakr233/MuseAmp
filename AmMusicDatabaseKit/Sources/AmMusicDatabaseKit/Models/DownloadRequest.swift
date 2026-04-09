import Foundation

public struct DownloadRequest: Sendable, Codable, Hashable {
    public let trackID: String
    public let albumID: String
    public let title: String
    public let artistName: String
    public let albumTitle: String?
    public let artworkURL: String?
    public let sourceURL: String?

    public init(
        trackID: String,
        albumID: String,
        title: String,
        artistName: String,
        albumTitle: String? = nil,
        artworkURL: String? = nil,
        sourceURL: String? = nil
    ) {
        self.trackID = trackID
        self.albumID = albumID
        self.title = title
        self.artistName = artistName
        self.albumTitle = albumTitle
        self.artworkURL = artworkURL
        self.sourceURL = sourceURL
    }
}
