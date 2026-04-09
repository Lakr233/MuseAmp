import Foundation

public struct SearchResponse: Decodable, Sendable {
    public let results: SearchResults

    public init(results: SearchResults) {
        self.results = results
    }
}
