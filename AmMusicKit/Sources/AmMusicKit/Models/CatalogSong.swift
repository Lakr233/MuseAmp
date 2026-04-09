import Foundation

public struct CatalogSong: Decodable, Hashable, Sendable, Identifiable {
    public let id: String
    public let type: String
    public let href: String?
    public let attributes: CatalogSongAttributes
    public let relationships: CatalogSongRelationships?

    public init(
        id: String,
        type: String,
        href: String?,
        attributes: CatalogSongAttributes,
        relationships: CatalogSongRelationships?
    ) {
        self.id = id
        self.type = type
        self.href = href
        self.attributes = attributes
        self.relationships = relationships
    }

    public static func == (lhs: CatalogSong, rhs: CatalogSong) -> Bool {
        lhs.id == rhs.id && lhs.type == rhs.type
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(type)
    }
}
