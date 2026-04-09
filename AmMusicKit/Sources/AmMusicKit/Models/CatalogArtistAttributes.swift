import Foundation

public struct CatalogArtistAttributes: Decodable, Hashable, Sendable {
    public let name: String
    public let url: String?
    public let artwork: Artwork?

    public init(name: String, url: String? = nil, artwork: Artwork?) {
        self.name = name
        self.url = url
        self.artwork = artwork
    }
}
