//
//  RemoteMusicService.swift
//  AmMusicKit
//
//  Created by @Lakr233 on 2026/04/11.
//

import Foundation

public final class RemoteMusicService: MusicService, Sendable {
    public let baseURL: URL

    private let authorizationToken: String?
    private let session: URLSession
    private let cacheStorageProvider: (any CacheStorageProvider)?
    private let cacheVersion: Int
    private let cacheTTL: TimeInterval = .infinity

    private let searchCache = ResponseCache<SearchResponse>()
    private let songCache = ResponseCache<SongResponse>()
    private let albumCache = ResponseCache<AlbumResponse>()
    private let playbackCache = ResponseCache<PlaybackInfo>()
    private let lyricsCache = ResponseCache<LyricsResponse>()
    private let coalescer = RequestCoalescer()
    private let decoder = JSONDecoder()

    public init(
        baseURL: URL,
        session: URLSession = .shared,
        cacheStorageProvider: (any CacheStorageProvider)? = nil,
        authorizationToken: String? = nil,
        cacheVersion: Int = 1,
    ) {
        self.baseURL = baseURL
        self.session = session
        self.cacheStorageProvider = cacheStorageProvider
        self.authorizationToken = authorizationToken
        self.cacheVersion = cacheVersion
    }

    public func search(
        query: String,
        type: SearchType,
        limit: Int = 20,
        offset: Int = 0,
        cacheSearchResponses: Bool = true,
        prefetchSongMetadata: Bool = true,
    ) async throws -> SearchResponse {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedQuery.isEmpty == false else {
            throw APIError.invalidRequest
        }

        let cache = cacheSearchResponses ? searchCache : nil
        let response = try await perform(
            .search(query: trimmedQuery, type: type, limit: limit, offset: offset),
            as: SearchResponse.self,
            cache: cache,
        )

        guard type == .song, prefetchSongMetadata else {
            return response
        }

        return await enrichSongSearchResponse(response)
    }

    public func album(id: String, storefront: String? = nil) async throws -> AlbumResponse {
        try await perform(
            .album(id: id, storefront: storefront), as: AlbumResponse.self, cache: albumCache,
        )
    }

    public func song(id: String, storefront: String? = nil) async throws -> SongResponse {
        try await perform(
            .song(id: id, storefront: storefront), as: SongResponse.self, cache: songCache,
        )
    }

    public func playback(id: String, storefront: String? = nil, redirect: Bool? = nil) async throws
        -> PlaybackInfo
    {
        try await perform(
            .playback(id: id, storefront: storefront, redirect: redirect), as: PlaybackInfo.self,
            cache: playbackCache,
        )
    }

    public func lyrics(id: String, storefront: String? = nil) async throws -> LyricsResponse {
        try await perform(
            .lyrics(id: id, storefront: storefront), as: LyricsResponse.self, cache: lyricsCache,
        )
    }

    // MARK: - Private

    private func perform<Response: Decodable & Sendable>(
        _ endpoint: APIEndpoint,
        as responseType: Response.Type,
        cache: ResponseCache<Response>? = nil,
    ) async throws -> Response {
        let request = try endpoint.urlRequest(
            baseURL: baseURL,
            authorizationToken: authorizationToken,
        )
        let cacheKey = request.url?.absoluteString ?? UUID().uuidString

        // 1. Memory fresh hit
        if let cache, let fresh = await cache.freshValue(forKey: cacheKey, ttl: cacheTTL) {
            return fresh
        }

        // 2. Disk fresh hit (only when cache is enabled)
        if cache != nil,
           let diskResult: Response = await loadFreshFromDisk(forKey: cacheKey, cache: cache)
        {
            return diskResult
        }

        // 3. Network request (through coalescer when cache is enabled, direct otherwise)
        let networkSession = session
        let networkRequest = request
        do {
            let rawData: Data =
                if cache != nil {
                    try await coalescer.perform(forKey: cacheKey) {
                        try await Self.fetchRawData(session: networkSession, request: networkRequest)
                    }
                } else {
                    try await Self.fetchRawData(session: networkSession, request: networkRequest)
                }

            let decoded = try decodeResponse(responseType, from: rawData, request: request)
            if let cache {
                await cache.setValue(decoded, forKey: cacheKey)
                await storeToDisk(data: rawData, forKey: cacheKey)
            }
            return decoded

        } catch {
            // Cancellation — always rethrow immediately
            if error is CancellationError {
                throw error
            }

            // Check if fallback-eligible
            guard cache != nil, isFallbackEligible(error) else {
                throw error
            }

            // Stale fallback
            try Task.checkCancellation()
            return try await staleFallback(
                forKey: cacheKey,
                responseType: responseType,
                cache: cache,
                originalError: error,
            )
        }
    }

    // MARK: - Network

    private static func fetchRawData(session: URLSession, request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            let host = request.url?.host ?? String(localized: "server", bundle: .module)
            throw APIError.transportFailed(
                message: String(
                    format: String(localized: "Request to %@ failed: %@", bundle: .module),
                    locale: .current,
                    host,
                    error.localizedDescription,
                ),
            )
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            throw APIError.requestFailed(statusCode: httpResponse.statusCode)
        }

        return data
    }

    // MARK: - Decode

    private func decodeResponse<Response: Decodable>(
        _ responseType: Response.Type,
        from data: Data,
        request: URLRequest,
    ) throws -> Response {
        do {
            return try decoder.decode(responseType, from: data)
        } catch {
            let context = decodeContext(for: error)
            let host = request.url?.host ?? String(localized: "server", bundle: .module)
            let message = String(
                format: String(localized: "Failed to decode %@ from %@: %@", bundle: .module),
                locale: .current,
                String(describing: responseType),
                host,
                context,
            )
            throw APIError.decodingFailed(message: message)
        }
    }

    // MARK: - Disk Cache

    private func loadFreshFromDisk<Response: Decodable & Sendable>(
        forKey key: String,
        cache: ResponseCache<Response>?,
    ) async -> Response? {
        guard let provider = cacheStorageProvider,
              let envelope = await provider.load(forKey: key)
        else { return nil }

        guard envelope.version == cacheVersion else {
            await provider.remove(forKey: key)
            return nil
        }

        guard Date().timeIntervalSince(envelope.cachedAt) < cacheTTL else {
            return nil
        }

        guard let decoded = try? decoder.decode(Response.self, from: envelope.data) else {
            await provider.remove(forKey: key)
            return nil
        }

        await cache?.setValue(decoded, forKey: key, cachedAt: envelope.cachedAt)
        return decoded
    }

    private func storeToDisk(data: Data, forKey key: String) async {
        guard let provider = cacheStorageProvider else { return }
        let envelope = CacheEnvelope(data: data, cachedAt: Date(), version: cacheVersion)
        await provider.store(envelope, forKey: key)
    }

    private func loadStaleFromDisk<Response: Decodable & Sendable>(
        forKey key: String,
    ) async -> Response? {
        guard let provider = cacheStorageProvider,
              let envelope = await provider.load(forKey: key)
        else { return nil }

        guard envelope.version == cacheVersion else {
            await provider.remove(forKey: key)
            return nil
        }

        guard let decoded = try? decoder.decode(Response.self, from: envelope.data) else {
            await provider.remove(forKey: key)
            return nil
        }

        return decoded
    }

    // MARK: - Stale Fallback

    private func isFallbackEligible(_ error: Error) -> Bool {
        switch error {
        case APIError.transportFailed:
            true
        case let APIError.requestFailed(statusCode):
            (500 ... 599).contains(statusCode)
        default:
            false
        }
    }

    private func staleFallback<Response: Decodable & Sendable>(
        forKey key: String,
        responseType _: Response.Type,
        cache: ResponseCache<Response>?,
        originalError: Error,
    ) async throws -> Response {
        if let cache, let stale = await cache.staleValue(forKey: key) {
            try Task.checkCancellation()
            return stale
        }

        if let diskStale: Response = await loadStaleFromDisk(forKey: key) {
            try Task.checkCancellation()
            return diskStale
        }

        throw originalError
    }

    // MARK: - Song Enrichment

    private func enrichSongSearchResponse(_ response: SearchResponse) async -> SearchResponse {
        guard let songs = response.results.songs, songs.data.isEmpty == false else {
            return response
        }

        let indexed = Array(songs.data.enumerated())
        let enrichedSongs = await withTaskGroup(
            of: (Int, CatalogSong).self,
            returning: [CatalogSong].self,
        ) { group in
            for (index, song) in indexed {
                group.addTask {
                    do {
                        let detail = try await self.song(id: song.id)
                        return (index, detail.data.first ?? song)
                    } catch {
                        return (index, song)
                    }
                }
            }
            var results = Array(repeating: indexed[0].element, count: indexed.count)
            for await (index, song) in group {
                results[index] = song
            }
            return results
        }

        return SearchResponse(
            results: SearchResults(
                songs: ResourceList(
                    href: songs.href,
                    next: songs.next,
                    data: enrichedSongs,
                ),
                albums: response.results.albums,
                artists: response.results.artists,
            ),
        )
    }

    // MARK: - Error Context

    private func decodeContext(for error: Error) -> String {
        switch error {
        case let DecodingError.keyNotFound(key, context):
            String(
                format: String(localized: "missing key '%@' at %@", bundle: .module),
                locale: .current,
                key.stringValue,
                codingPath(from: context.codingPath),
            )
        case let DecodingError.typeMismatch(type, context):
            String(
                format: String(localized: "type mismatch for %@ at %@", bundle: .module),
                locale: .current,
                String(describing: type),
                codingPath(from: context.codingPath),
            )
        case let DecodingError.valueNotFound(type, context):
            String(
                format: String(localized: "missing value for %@ at %@", bundle: .module),
                locale: .current,
                String(describing: type),
                codingPath(from: context.codingPath),
            )
        case let DecodingError.dataCorrupted(context):
            String(
                format: String(localized: "data corrupted at %@: %@", bundle: .module),
                locale: .current,
                codingPath(from: context.codingPath),
                context.debugDescription,
            )
        default:
            error.localizedDescription
        }
    }

    private func codingPath(from codingPath: [CodingKey]) -> String {
        guard codingPath.isEmpty == false else {
            return String(localized: "<root>", bundle: .module)
        }
        return codingPath.map(\.stringValue).joined(separator: ".")
    }
}
