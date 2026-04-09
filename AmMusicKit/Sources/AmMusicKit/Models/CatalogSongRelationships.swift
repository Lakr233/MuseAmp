import Foundation

public struct CatalogSongRelationships: Decodable, Sendable {
    public let artists: ResourceList<CatalogArtist>?
    public let albums: ResourceList<CatalogAlbum>?

    public init(
        artists: ResourceList<CatalogArtist>? = nil,
        albums: ResourceList<CatalogAlbum>? = nil
    ) {
        self.artists = artists
        self.albums = albums
    }
}
