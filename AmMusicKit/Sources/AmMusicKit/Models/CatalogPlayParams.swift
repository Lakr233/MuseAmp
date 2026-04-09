import Foundation

public struct CatalogPlayParams: Decodable, Hashable, Sendable {
    public let id: String
    public let kind: String

    public init(id: String, kind: String) {
        self.id = id
        self.kind = kind
    }
}
