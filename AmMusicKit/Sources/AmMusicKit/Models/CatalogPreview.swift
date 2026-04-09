import Foundation

public struct CatalogPreview: Decodable, Hashable, Sendable {
    public let url: String

    public init(url: String) {
        self.url = url
    }
}
