import Foundation

public struct Artwork: Decodable, Hashable, Sendable {
    public let width: Int?
    public let height: Int?
    public let url: String?

    public init(width: Int?, height: Int?, url: String?) {
        self.width = width
        self.height = height
        self.url = url
    }

    public func imageURL(width: Int = 160, height: Int = 160) -> URL? {
        guard let url, url.isEmpty == false else {
            return nil
        }

        let resolvedURL = url
            .replacingOccurrences(of: "{w}", with: "\(width)")
            .replacingOccurrences(of: "{h}", with: "\(height)")
        return URL(string: resolvedURL)
    }
}
