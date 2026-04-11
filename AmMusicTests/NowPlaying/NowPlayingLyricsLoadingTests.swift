@testable import AmMusic
import AmMusicKit
import Testing

@Suite(.serialized)
struct NowPlayingLyricsLoadingTests {
    @Test
    func `Lyrics 404 responses are cached as unavailable`() {
        #expect(shouldCacheUnavailableLyricsResult(for: APIError.requestFailed(statusCode: 404)))
        #expect(!shouldCacheUnavailableLyricsResult(for: APIError.requestFailed(statusCode: 500)))
        #expect(!shouldCacheUnavailableLyricsResult(for: APIError.invalidResponse))
    }
}
