import Foundation

public struct CatalogSongAttributes: Decodable, Hashable, Sendable {
    public let name: String
    public let artistName: String
    public let albumName: String?
    public let url: String?
    public let durationInMillis: Int?
    public let trackNumber: Int?
    public let discNumber: Int?
    public let releaseDate: String?
    public let isrc: String?
    public let composerName: String?
    public let audioTraits: [String]?
    public let contentRating: String?
    public let hasLyrics: Bool?
    public let hasTimeSyncedLyrics: Bool?
    public let previews: [CatalogPreview]?
    public let extendedAssetUrls: CatalogExtendedAssetURLs?
    public let artwork: Artwork?
    public let playParams: CatalogPlayParams?

    public init(
        name: String,
        artistName: String,
        albumName: String? = nil,
        url: String? = nil,
        durationInMillis: Int? = nil,
        trackNumber: Int? = nil,
        discNumber: Int? = nil,
        releaseDate: String? = nil,
        isrc: String? = nil,
        composerName: String? = nil,
        audioTraits: [String]? = nil,
        contentRating: String? = nil,
        hasLyrics: Bool? = nil,
        hasTimeSyncedLyrics: Bool? = nil,
        previews: [CatalogPreview]? = nil,
        extendedAssetUrls: CatalogExtendedAssetURLs? = nil,
        artwork: Artwork? = nil,
        playParams: CatalogPlayParams? = nil
    ) {
        self.name = name
        self.artistName = artistName
        self.albumName = albumName
        self.url = url
        self.durationInMillis = durationInMillis
        self.trackNumber = trackNumber
        self.discNumber = discNumber
        self.releaseDate = releaseDate
        self.isrc = isrc
        self.composerName = composerName
        self.audioTraits = audioTraits
        self.contentRating = contentRating
        self.hasLyrics = hasLyrics
        self.hasTimeSyncedLyrics = hasTimeSyncedLyrics
        self.previews = previews
        self.extendedAssetUrls = extendedAssetUrls
        self.artwork = artwork
        self.playParams = playParams
    }
}
