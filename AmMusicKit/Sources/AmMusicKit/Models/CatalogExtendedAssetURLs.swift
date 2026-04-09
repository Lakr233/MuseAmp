import Foundation

public struct CatalogExtendedAssetURLs: Decodable, Hashable, Sendable {
    public let enhancedHls: String?

    public init(enhancedHls: String?) {
        self.enhancedHls = enhancedHls
    }
}
