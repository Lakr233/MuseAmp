import Foundation

public struct LyricsResponse: Decodable, Hashable, Sendable {
    public let lyrics: String

    public init(lyrics: String) {
        self.lyrics = lyrics
    }
}
