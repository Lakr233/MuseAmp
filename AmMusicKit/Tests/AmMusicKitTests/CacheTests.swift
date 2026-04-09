@testable import AmMusicKit
import Foundation
import Testing

// MARK: - Mock URLProtocol

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

// MARK: - Mock CacheStorageProvider

private actor MockDiskStore: CacheStorageProvider {
    var storage: [String: CacheEnvelope] = [:]
    var loadCount = 0
    var storeCount = 0
    var removeCount = 0
    var removeAllCount = 0

    func load(forKey key: String) -> CacheEnvelope? {
        loadCount += 1
        return storage[key]
    }

    func store(_ envelope: CacheEnvelope, forKey key: String) {
        storeCount += 1
        storage[key] = envelope
    }

    func remove(forKey key: String) {
        removeCount += 1
        storage[key] = nil
    }

    func removeAll() {
        removeAllCount += 1
        storage.removeAll()
    }
}

// MARK: - Test Helpers

private let testBaseURL = URL(string: "https://test.example.com")!

private func makeMockSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
}

private func songJSON(id: String = "123") -> String {
    """
    {
        "data": [{
            "id": "\(id)",
            "type": "songs",
            "attributes": {
                "name": "Test Song",
                "artistName": "Test Artist"
            }
        }]
    }
    """
}

private func makeSuccessHandler(json: String? = nil) -> (URLRequest) throws -> (
    Data, HTTPURLResponse
) {
    { request in
        let body = json ?? songJSON()
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
        )!
        return (Data(body.utf8), response)
    }
}

private func makeErrorHandler(statusCode: Int) -> (URLRequest) throws -> (Data, HTTPURLResponse) {
    { request in
        let response = HTTPURLResponse(
            url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil
        )!
        return (Data(), response)
    }
}

private func cacheKey(forSongID id: String) -> String {
    testBaseURL.appendingPathComponent("song/\(id)").absoluteString
}

// MARK: - Simple thread-safe counter

private final class AtomicInt: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Int
    init(_ initial: Int = 0) {
        _value = initial
    }

    func increment() {
        lock.lock()
        _value += 1
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }
}

// MARK: - ResponseCache Tests

struct ResponseCacheTests {
    @Test("Fresh value returned within TTL")
    func freshValueWithinTTL() async {
        let cache = ResponseCache<String>()
        await cache.setValue("hello", forKey: "k1")
        let result = await cache.freshValue(forKey: "k1", ttl: 3600)
        #expect(result == "hello")
    }

    @Test("Fresh value nil after TTL expires")
    func freshValueExpired() async {
        let cache = ResponseCache<String>()
        await cache.setValue("old", forKey: "k1", cachedAt: Date().addingTimeInterval(-7200))
        let result = await cache.freshValue(forKey: "k1", ttl: 3600)
        #expect(result == nil)
    }

    @Test("Stale value returned for expired entry within maxAge")
    func staleValueReturned() async {
        let cache = ResponseCache<String>()
        await cache.setValue("old", forKey: "k1", cachedAt: Date().addingTimeInterval(-7200))
        let result = await cache.staleValue(forKey: "k1")
        #expect(result == "old")
    }

    @Test("Stale value nil beyond maxAge")
    func staleValueBeyondMaxAge() async {
        let cache = ResponseCache<String>()
        await cache.setValue(
            "ancient", forKey: "k1", cachedAt: Date().addingTimeInterval(-8 * 24 * 3600)
        )
        let result = await cache.staleValue(forKey: "k1")
        #expect(result == nil)
    }

    @Test("setValue with cachedAt preserves original timestamp")
    func setValueWithCachedAt() async {
        let cache = ResponseCache<String>()
        await cache.setValue("disk", forKey: "k1", cachedAt: Date().addingTimeInterval(-3000))
        #expect(await cache.freshValue(forKey: "k1", ttl: 3600) == "disk")
        #expect(await cache.freshValue(forKey: "k1", ttl: 2000) == nil)
    }

    @Test("Missing key returns nil")
    func missingKey() async {
        let cache = ResponseCache<String>()
        #expect(await cache.freshValue(forKey: "x", ttl: 3600) == nil)
        #expect(await cache.staleValue(forKey: "x") == nil)
    }
}

// MARK: - RequestCoalescer Tests

struct RequestCoalescerTests {
    @Test("Different keys run independently")
    func differentKeys() async throws {
        let coalescer = RequestCoalescer()
        let d1 = try await coalescer.perform(forKey: "a") { Data("a".utf8) }
        let d2 = try await coalescer.perform(forKey: "b") { Data("b".utf8) }
        #expect(d1 == Data("a".utf8))
        #expect(d2 == Data("b".utf8))
    }

    @Test("Propagates work errors")
    func propagatesErrors() async {
        let coalescer = RequestCoalescer()
        await #expect(throws: APIError.self) {
            try await coalescer.perform(forKey: "k") {
                throw APIError.transportFailed(message: "offline")
            }
        }
    }
}

// MARK: - CacheEnvelope Tests

struct CacheEnvelopeTests {
    @Test("CacheEnvelope stores data and metadata")
    func construction() {
        let data = Data("test".utf8)
        let date = Date()
        let envelope = CacheEnvelope(data: data, cachedAt: date, version: 2)
        #expect(envelope.data == data)
        #expect(envelope.cachedAt == date)
        #expect(envelope.version == 2)
    }
}

// MARK: - RemoteMusicService Cache Integration Tests

@Suite(.serialized)
struct ServiceCacheTests {
    @Test("Authorization header adds Bearer token")
    func authorizationHeader() async throws {
        let session = makeMockSession()
        MockURLProtocol.handler = { request in
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
            return try makeSuccessHandler()(request)
        }

        let service = RemoteMusicService(
            baseURL: testBaseURL,
            session: session,
            authorizationToken: "test-token"
        )
        _ = try await service.song(id: "123")
    }

    @Test("Authorization header preserves explicit Bearer prefix")
    func authorizationHeaderWithExistingPrefix() async throws {
        let session = makeMockSession()
        MockURLProtocol.handler = { request in
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer already-prefixed")
            return try makeSuccessHandler()(request)
        }

        let service = RemoteMusicService(
            baseURL: testBaseURL,
            session: session,
            authorizationToken: "Bearer already-prefixed"
        )
        _ = try await service.song(id: "123")
    }

    @Test("Fresh memory cache hit skips network")
    func freshMemoryHit() async throws {
        let session = makeMockSession()
        let requestCount = AtomicInt()
        MockURLProtocol.handler = { request in
            requestCount.increment()
            return try makeSuccessHandler()(request)
        }

        let service = RemoteMusicService(baseURL: testBaseURL, session: session)
        let first = try await service.song(id: "123")
        #expect(first.data.first?.id == "123")
        #expect(requestCount.value == 1)

        let second = try await service.song(id: "123")
        #expect(second.data.first?.id == "123")
        #expect(requestCount.value == 1)
    }

    @Test("Disk cache hit on cold start")
    func diskCacheHit() async throws {
        let session = makeMockSession()
        let diskStore = MockDiskStore()

        let envelope = CacheEnvelope(data: Data(songJSON().utf8), cachedAt: Date(), version: 1)
        await diskStore.store(envelope, forKey: cacheKey(forSongID: "123"))

        var networkHit = false
        MockURLProtocol.handler = { request in
            networkHit = true
            return try makeSuccessHandler()(request)
        }

        let service = RemoteMusicService(
            baseURL: testBaseURL, session: session, cacheStorageProvider: diskStore
        )
        let response = try await service.song(id: "123")
        #expect(response.data.first?.id == "123")
        #expect(networkHit == false)
    }

    @Test("Stale fallback on transport error from disk")
    func staleFallbackOnTransportError() async throws {
        let session = makeMockSession()
        let diskStore = MockDiskStore()

        let expiredEnvelope = CacheEnvelope(
            data: Data(songJSON(id: "stale1").utf8),
            cachedAt: Date().addingTimeInterval(-7200),
            version: 1
        )
        await diskStore.store(expiredEnvelope, forKey: cacheKey(forSongID: "stale1"))

        MockURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }

        let service = RemoteMusicService(
            baseURL: testBaseURL, session: session, cacheStorageProvider: diskStore
        )
        let response = try await service.song(id: "stale1")
        #expect(response.data.first?.id == "stale1")
    }

    @Test("Stale fallback on 5xx error from disk")
    func staleFallbackOn5xx() async throws {
        let session = makeMockSession()
        let diskStore = MockDiskStore()

        let expiredEnvelope = CacheEnvelope(
            data: Data(songJSON(id: "stale5xx").utf8),
            cachedAt: Date().addingTimeInterval(-7200),
            version: 1
        )
        await diskStore.store(expiredEnvelope, forKey: cacheKey(forSongID: "stale5xx"))

        MockURLProtocol.handler = makeErrorHandler(statusCode: 503)

        let service = RemoteMusicService(
            baseURL: testBaseURL, session: session, cacheStorageProvider: diskStore
        )
        let response = try await service.song(id: "stale5xx")
        #expect(response.data.first?.id == "stale5xx")
    }

    @Test("Cached disk entry bypasses 4xx responses")
    func cachedDiskEntryBypasses4xx() async throws {
        let session = makeMockSession()
        let diskStore = MockDiskStore()

        let cachedEnvelope = CacheEnvelope(
            data: Data(songJSON().utf8),
            cachedAt: Date().addingTimeInterval(-7200),
            version: 1
        )
        await diskStore.store(cachedEnvelope, forKey: cacheKey(forSongID: "404song"))

        var networkHit = false
        MockURLProtocol.handler = { request in
            networkHit = true
            return try makeErrorHandler(statusCode: 404)(request)
        }

        let service = RemoteMusicService(
            baseURL: testBaseURL, session: session, cacheStorageProvider: diskStore
        )

        let response = try await service.song(id: "404song")
        #expect(response.data.first?.id == "123")
        #expect(networkHit == false)
    }

    @Test("Cached disk entry bypasses decode failures")
    func cachedDiskEntryBypassesDecodeFailures() async throws {
        let session = makeMockSession()
        let diskStore = MockDiskStore()

        let cachedEnvelope = CacheEnvelope(
            data: Data(songJSON().utf8),
            cachedAt: Date().addingTimeInterval(-7200),
            version: 1
        )
        await diskStore.store(cachedEnvelope, forKey: cacheKey(forSongID: "badsong"))

        var networkHit = false
        MockURLProtocol.handler = { request in
            networkHit = true
            return try makeSuccessHandler(json: "{ invalid json !!!")(request)
        }

        let service = RemoteMusicService(
            baseURL: testBaseURL, session: session, cacheStorageProvider: diskStore
        )

        let response = try await service.song(id: "badsong")
        #expect(response.data.first?.id == "123")
        #expect(networkHit == false)
    }

    @Test("Disk writes happen on network success")
    func diskWriteOnSuccess() async throws {
        let session = makeMockSession()
        let diskStore = MockDiskStore()
        MockURLProtocol.handler = makeSuccessHandler()

        let service = RemoteMusicService(
            baseURL: testBaseURL, session: session, cacheStorageProvider: diskStore
        )
        _ = try await service.song(id: "123")

        #expect(await diskStore.storeCount == 1)
    }

    @Test("Corrupt disk entry gets removed and falls through to network")
    func corruptDiskEntryRemoved() async throws {
        let session = makeMockSession()
        let diskStore = MockDiskStore()

        let corruptEnvelope = CacheEnvelope(data: Data("not json".utf8), cachedAt: Date(), version: 1)
        await diskStore.store(corruptEnvelope, forKey: cacheKey(forSongID: "corrupt1"))

        MockURLProtocol.handler = makeSuccessHandler(json: songJSON(id: "corrupt1"))

        let service = RemoteMusicService(
            baseURL: testBaseURL, session: session, cacheStorageProvider: diskStore
        )
        let response = try await service.song(id: "corrupt1")
        #expect(response.data.first?.id == "corrupt1")
        #expect(await diskStore.removeCount >= 1)
    }

    @Test("Version mismatch disk entry gets removed")
    func versionMismatchRemoved() async throws {
        let session = makeMockSession()
        let diskStore = MockDiskStore()

        let oldEnvelope = CacheEnvelope(
            data: Data(songJSON().utf8), cachedAt: Date(), version: 99
        )
        await diskStore.store(oldEnvelope, forKey: cacheKey(forSongID: "ver1"))

        MockURLProtocol.handler = makeSuccessHandler(json: songJSON(id: "ver1"))

        let service = RemoteMusicService(
            baseURL: testBaseURL, session: session, cacheStorageProvider: diskStore
        )
        let response = try await service.song(id: "ver1")
        #expect(response.data.first?.id == "ver1")
        #expect(await diskStore.removeCount >= 1)
    }

    @Test("cacheSearchResponses false skips all caching")
    func cacheOptOut() async throws {
        let session = makeMockSession()
        let diskStore = MockDiskStore()

        let searchJSON = """
        {
            "results": {
                "songs": {
                    "data": [{
                        "id": "1",
                        "type": "songs",
                        "attributes": {"name": "S", "artistName": "A"}
                    }]
                }
            }
        }
        """

        let requestCount = AtomicInt()
        MockURLProtocol.handler = { request in
            requestCount.increment()
            return try makeSuccessHandler(json: searchJSON)(request)
        }

        let service = RemoteMusicService(
            baseURL: testBaseURL, session: session, cacheStorageProvider: diskStore
        )

        _ = try await service.search(
            query: "test", type: .song, limit: 1, offset: 0,
            cacheSearchResponses: false, prefetchSongMetadata: false
        )
        _ = try await service.search(
            query: "test", type: .song, limit: 1, offset: 0,
            cacheSearchResponses: false, prefetchSongMetadata: false
        )

        #expect(requestCount.value == 2)
        #expect(await diskStore.storeCount == 0)
    }

    @Test("Disk cache remains fresh beyond the previous one-hour TTL")
    func diskCacheNeverExpires() async throws {
        let session = makeMockSession()
        let diskStore = MockDiskStore()

        let oldCacheDate = Date().addingTimeInterval(-30 * 24 * 3600)
        let envelope = CacheEnvelope(data: Data(songJSON().utf8), cachedAt: oldCacheDate, version: 1)
        await diskStore.store(envelope, forKey: cacheKey(forSongID: "123"))

        var networkHit = false
        MockURLProtocol.handler = { request in
            networkHit = true
            return try makeSuccessHandler()(request)
        }

        let service = RemoteMusicService(
            baseURL: testBaseURL, session: session, cacheStorageProvider: diskStore
        )

        let r1 = try await service.song(id: "123")
        #expect(r1.data.first?.id == "123")
        #expect(networkHit == false)
    }

    @Test("Stale disk fallback rejects version mismatch")
    func staleDiskFallbackVersionMismatch() async throws {
        let session = makeMockSession()
        let diskStore = MockDiskStore()

        let oldVersionEnvelope = CacheEnvelope(
            data: Data(songJSON().utf8),
            cachedAt: Date().addingTimeInterval(-7200),
            version: 99
        )
        await diskStore.store(oldVersionEnvelope, forKey: cacheKey(forSongID: "vmm1"))

        MockURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }

        let service = RemoteMusicService(
            baseURL: testBaseURL, session: session, cacheStorageProvider: diskStore
        )

        await #expect(throws: APIError.self) {
            try await service.song(id: "vmm1")
        }
    }
}
