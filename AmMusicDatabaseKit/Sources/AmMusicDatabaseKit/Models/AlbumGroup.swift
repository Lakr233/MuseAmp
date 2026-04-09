import Foundation

public struct AlbumGroup: Sendable, Codable, Hashable, Identifiable {
    public var id: String {
        albumID
    }

    public let albumID: String
    public let albumTitle: String
    public let artistName: String
    public let albumArtistName: String?
    public let trackCount: Int
    public let artworkTrackID: String?
    public let totalDurationSeconds: Double

    public init(
        albumID: String,
        albumTitle: String,
        artistName: String,
        albumArtistName: String? = nil,
        trackCount: Int,
        artworkTrackID: String? = nil,
        totalDurationSeconds: Double
    ) {
        self.albumID = albumID
        self.albumTitle = albumTitle
        self.artistName = artistName
        self.albumArtistName = albumArtistName
        self.trackCount = trackCount
        self.artworkTrackID = artworkTrackID
        self.totalDurationSeconds = totalDurationSeconds
    }
}
