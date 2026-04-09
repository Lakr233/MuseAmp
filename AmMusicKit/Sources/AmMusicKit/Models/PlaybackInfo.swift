import Foundation

public struct PlaybackInfo: Decodable, Hashable, Sendable {
    public let playbackURL: String
    public let size: Int64
    public let title: String
    public let artist: String
    public let artistID: String
    public let album: String
    public let albumID: String
    public let codec: String

    public init(
        playbackURL: String,
        size: Int64,
        title: String,
        artist: String,
        artistID: String,
        album: String,
        albumID: String,
        codec: String
    ) {
        self.playbackURL = playbackURL
        self.size = size
        self.title = title
        self.artist = artist
        self.artistID = artistID
        self.album = album
        self.albumID = albumID
        self.codec = codec
    }

    enum CodingKeys: String, CodingKey {
        case playbackURL = "playbackUrl"
        case size
        case title
        case artist
        case artistID = "artistId"
        case album
        case albumID = "albumId"
        case codec
    }
}
