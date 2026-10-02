import Foundation
@testable import SubsonicClientKit
import Testing

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Data, HTTPURLResponse))?

    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (data, response) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private actor MockDiskStore: CacheStorageProvider {
    var storage: [String: CacheEnvelope] = [:]
    var storeCount = 0

    func load(forKey key: String) -> CacheEnvelope? {
        storage[key]
    }

    func store(_ envelope: CacheEnvelope, forKey key: String) {
        storeCount += 1
        storage[key] = envelope
    }

    func remove(forKey key: String) {
        storage[key] = nil
    }

    func removeAll() {
        storage.removeAll()
    }
}

private let testBaseURL = URL(string: "https://cache.example.com/rest")!

private func makeMockSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: configuration)
}

private func wrappedSongResponse(id: String = "song-1") throws -> Data {
    try JSONSerialization.data(withJSONObject: [
        "subsonic-response": [
            "status": "ok",
            "version": "1.16.1",
            "song": [
                "id": id,
                "title": "Song \(id)",
                "album": "Album",
                "albumId": "album-1",
                "artist": "Artist",
                "artistId": "artist-1",
                "coverArt": "cover-1",
                "duration": 120,
                "track": 1,
                "suffix": "m4a",
                "contentType": "audio/m4a",
                "size": 1000,
            ],
        ],
    ])
}

private func wrappedLyricsResponse(_ text: String) throws -> Data {
    try JSONSerialization.data(withJSONObject: [
        "subsonic-response": [
            "status": "ok",
            "version": "1.16.1",
            "lyrics": ["value": text],
        ],
    ])
}

private func cacheKey(forSongID id: String) -> String {
    "\(testBaseURL.absoluteString)|demo|song:\(id)"
}

private final class AtomicInt: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    func increment() {
        lock.lock()
        storage += 1
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

struct ResponseCacheTests {
    @Test
    func `Fresh value returned within TTL`() async {
        let cache = ResponseCache<String>()
        await cache.setValue("hello", forKey: "k1")
        let result = await cache.freshValue(forKey: "k1", ttl: 3600)
        #expect(result == "hello")
    }

    @Test
    func `Stale value returned for expired entry`() async {
        let cache = ResponseCache<String>()
        await cache.setValue("old", forKey: "k1", cachedAt: Date().addingTimeInterval(-7200))
        let result = await cache.staleValue(forKey: "k1")
        #expect(result == "old")
    }
}

@Suite(.serialized)
struct SubsonicCacheTests {
    @Test
    func `Fresh memory cache hit skips network`() async throws {
        let session = makeMockSession()
        let requestCount = AtomicInt()
        MockURLProtocol.handler = { request in
            requestCount.increment()
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return try (wrappedSongResponse(), response)
        }

        let service = SubsonicMusicService(
            baseURL: testBaseURL,
            username: "demo",
            password: "secret",
            session: session,
        )

        let first = try await service.song(id: "song-1")
        let second = try await service.song(id: "song-1")
        #expect(first.firstSong?.id == "song-1")
        #expect(second.firstSong?.id == "song-1")
        #expect(requestCount.value == 1)
    }

    @Test
    func `Disk cache hit on cold start bypasses network`() async throws {
        let session = makeMockSession()
        let diskStore = MockDiskStore()
        try await diskStore.store(
            CacheEnvelope(data: wrappedSongResponse(), cachedAt: Date(), version: 2),
            forKey: cacheKey(forSongID: "song-1"),
        )

        var networkHit = false
        MockURLProtocol.handler = { request in
            networkHit = true
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return try (wrappedSongResponse(), response)
        }

        let service = SubsonicMusicService(
            baseURL: testBaseURL,
            username: "demo",
            password: "secret",
            session: session,
            cacheStorageProvider: diskStore,
        )

        let response = try await service.song(id: "song-1")
        #expect(response.firstSong?.id == "song-1")
        #expect(networkHit == false)
    }

    @Test
    func `Network success writes to disk cache`() async throws {
        let session = makeMockSession()
        let diskStore = MockDiskStore()
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return try (wrappedSongResponse(), response)
        }

        let service = SubsonicMusicService(
            baseURL: testBaseURL,
            username: "demo",
            password: "secret",
            session: session,
            cacheStorageProvider: diskStore,
        )

        _ = try await service.song(id: "song-1")
        #expect(await diskStore.storeCount == 1)
    }

    @Test
    func `Lyrics bypassing the cache refetch and replace the cached response`() async throws {
        let session = makeMockSession()
        let requestCount = AtomicInt()
        let serverLyrics = LockedString("[00:01.00]Old line")
        MockURLProtocol.handler = { request in
            requestCount.increment()
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return try (wrappedLyricsResponse(serverLyrics.value), response)
        }

        let service = SubsonicMusicService(
            baseURL: testBaseURL,
            username: "demo",
            password: "secret",
            session: session,
        )

        let first = try await service.lyrics(id: "song-1")
        serverLyrics.value = "[00:01.00]New line"
        let cached = try await service.lyrics(id: "song-1")
        let reloaded = try await service.lyrics(id: "song-1", bypassCache: true)
        let afterReload = try await service.lyrics(id: "song-1")

        #expect(first.lyrics == "[00:01.00]Old line")
        #expect(cached.lyrics == "[00:01.00]Old line")
        #expect(reloaded.lyrics == "[00:01.00]New line")
        #expect(afterReload.lyrics == "[00:01.00]New line")
        #expect(requestCount.value == 2)
    }

    @Test
    func `Lyrics bypassing the cache report a failed request instead of the cached response`() async throws {
        let session = makeMockSession()
        let shouldFail = LockedString("no")
        MockURLProtocol.handler = { request in
            if shouldFail.value == "yes" {
                throw URLError(.notConnectedToInternet)
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return try (wrappedLyricsResponse("[00:01.00]Cached line"), response)
        }

        let service = SubsonicMusicService(
            baseURL: testBaseURL,
            username: "demo",
            password: "secret",
            session: session,
        )

        _ = try await service.lyrics(id: "song-1")
        shouldFail.value = "yes"

        await #expect(throws: APIError.self) {
            _ = try await service.lyrics(id: "song-1", bypassCache: true)
        }
        let cached = try await service.lyrics(id: "song-1")
        #expect(cached.lyrics == "[00:01.00]Cached line")
    }
}

private final class LockedString: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: String

    init(_ value: String) {
        storage = value
    }

    var value: String {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
        set {
            lock.lock()
            storage = newValue
            lock.unlock()
        }
    }
}
