import Foundation

public struct CatalogAlbumAttributes: Decodable, Hashable, Sendable {
    public let artistName: String
    public let name: String
    public let url: String?
    public let trackCount: Int?
    public let releaseDate: String?
    public let recordLabel: String?
    public let upc: String?
    public let copyright: String?
    public let genreNames: [String]?
    public let contentRating: String?
    public let audioTraits: [String]?
    public let isSingle: Bool?
    public let isComplete: Bool?
    public let isCompilation: Bool?
    public let artwork: Artwork?
    public let playParams: CatalogPlayParams?

    public init(
        artistName: String,
        name: String,
        url: String? = nil,
        trackCount: Int? = nil,
        releaseDate: String? = nil,
        recordLabel: String? = nil,
        upc: String? = nil,
        copyright: String? = nil,
        genreNames: [String]? = nil,
        audioTraits: [String]? = nil,
        contentRating: String? = nil,
        isSingle: Bool? = nil,
        isComplete: Bool? = nil,
        isCompilation: Bool? = nil,
        artwork: Artwork? = nil,
        playParams: CatalogPlayParams? = nil
    ) {
        self.artistName = artistName
        self.name = name
        self.url = url
        self.trackCount = trackCount
        self.releaseDate = releaseDate
        self.recordLabel = recordLabel
        self.upc = upc
        self.copyright = copyright
        self.genreNames = genreNames
        self.audioTraits = audioTraits
        self.contentRating = contentRating
        self.isSingle = isSingle
        self.isComplete = isComplete
        self.isCompilation = isCompilation
        self.artwork = artwork
        self.playParams = playParams
    }
}
