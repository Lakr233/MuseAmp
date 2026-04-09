import Foundation

public struct AlbumResponse: Decodable, Sendable {
    public let href: String?
    public let next: String?
    public let data: [CatalogAlbum]

    public init(href: String?, next: String?, data: [CatalogAlbum]) {
        self.href = href
        self.next = next
        self.data = data
    }

    public var firstAlbum: CatalogAlbum? {
        data.first
    }
}
