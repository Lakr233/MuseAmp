import Foundation

public struct ImportedTrackMetadata: Sendable, Codable, Hashable {
    public let trackID: String
    public let albumID: String
    public let title: String
    public let artistName: String
    public let albumTitle: String
    public let albumArtistName: String?
    public let durationSeconds: TimeInterval?
    public let trackNumber: Int?
    public let discNumber: Int?
    public let genreName: String?
    public let composerName: String?
    public let releaseDate: String?
    public let lyrics: String?
    public let sourceKind: TrackSourceKind

    public init(
        trackID: String,
        albumID: String,
        title: String,
        artistName: String,
        albumTitle: String,
        albumArtistName: String? = nil,
        durationSeconds: TimeInterval? = nil,
        trackNumber: Int? = nil,
        discNumber: Int? = nil,
        genreName: String? = nil,
        composerName: String? = nil,
        releaseDate: String? = nil,
        lyrics: String? = nil,
        sourceKind: TrackSourceKind
    ) {
        self.trackID = trackID
        self.albumID = albumID
        self.title = title
        self.artistName = artistName
        self.albumTitle = albumTitle
        self.albumArtistName = albumArtistName
        self.durationSeconds = durationSeconds
        self.trackNumber = trackNumber
        self.discNumber = discNumber
        self.genreName = genreName
        self.composerName = composerName
        self.releaseDate = releaseDate
        self.lyrics = lyrics
        self.sourceKind = sourceKind
    }
}
