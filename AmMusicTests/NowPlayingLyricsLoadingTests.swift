@testable import AmMusic
import AmMusicKit
import Testing

@Suite(.serialized)
struct NowPlayingLyricsLoadingTests {
    @Test("Lyrics 404 responses are cached as unavailable")
    func cacheUnavailableLyricsFor404() {
        #expect(shouldCacheUnavailableLyricsResult(for: APIError.requestFailed(statusCode: 404)))
        #expect(!shouldCacheUnavailableLyricsResult(for: APIError.requestFailed(statusCode: 500)))
        #expect(!shouldCacheUnavailableLyricsResult(for: APIError.invalidResponse))
    }
}
