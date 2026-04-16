//
//  SubsonicMusicService.swift
//  SubsonicClientKit
//
//  Created by @Lakr233 on 2026/04/14.
//

import Foundation

public final class SubsonicMusicService: Sendable {
    public let baseURL: URL

    private let username: String
    private let password: String
    private let session: URLSession
    private let cacheStorageProvider: (any CacheStorageProvider)?
    private let cacheVersion: Int
    private let cacheTTL: TimeInterval = .infinity
    private let authLock = NSLock()
    private let tokenSalt = UUID().uuidString.replacingOccurrences(of: "-", with: "")

    private nonisolated(unsafe) var authMode: SubsonicAuthenticationMode = .token

    private let searchCache = ResponseCache<SearchResponse>()
    private let artistCache = ResponseCache<ArtistResponse?>()
    private let songCache = ResponseCache<SongResponse>()
    private let albumCache = ResponseCache<AlbumResponse>()
    private let playbackCache = ResponseCache<PlaybackInfo>()
    private let lyricsCache = ResponseCache<LyricsResponse>()
    private let coalescer = RequestCoalescer()
    private let decoder = JSONDecoder()

    public init(
        baseURL: URL,
        username: String,
        password: String,
        session: URLSession = .shared,
        cacheStorageProvider: (any CacheStorageProvider)? = nil,
        cacheVersion: Int = 2,
    ) {
        self.baseURL = baseURL
        self.username = username
        self.password = password
        self.session = session
        self.cacheStorageProvider = cacheStorageProvider
        self.cacheVersion = cacheVersion
    }

    public func ping() async throws {
        _ = try await perform(.ping, cache: nil) { (payload: SubsonicPingPayload) in
            payload
        }
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
            cache: cache,
        ) { (payload: SubsonicSearchResultPayload) in
            Self.mapSearchResponse(
                payload.searchResult,
                type: type,
                limit: limit,
                offset: offset,
                artworkBuilder: { [serviceBaseURL = self.baseURL, weak self] coverArtID in
                    self?.artworkTemplateURL(coverArtID: coverArtID, baseURL: serviceBaseURL)
                },
            )
        }

        guard type == .song, prefetchSongMetadata else {
            return response
        }

        return await enrichSongSearchResponse(response)
    }

    public func album(id: String) async throws -> AlbumResponse {
        try await perform(.album(id: id), cache: albumCache) { (payload: SubsonicAlbumPayload) in
            guard let album = payload.album else {
                return AlbumResponse(href: nil, next: nil, data: [])
            }
            let mapped = Self.mapAlbum(
                album,
                artworkURL: self.artworkTemplateURL(coverArtID: album.coverArt),
            )
            return AlbumResponse(href: nil, next: nil, data: [mapped])
        }
    }

    public func artist(id: String) async throws -> ArtistResponse? {
        try await perform(.artist(id: id), cache: artistCache) { (payload: SubsonicArtistPayload) in
            guard let artist = payload.artist else {
                return nil
            }

            let artistArtworkURL = artist.artistImageUrl ?? self.artworkTemplateURL(coverArtID: artist.coverArt)
            let mappedArtist = Self.mapArtist(artist, artworkURL: artistArtworkURL)
            let mappedAlbums = artist.albums.map { album in
                Self.mapAlbum(album, artworkURL: self.artworkTemplateURL(coverArtID: album.coverArt))
            }

            return ArtistResponse(
                artist: mappedArtist,
                albums: mappedAlbums,
                albumCount: artist.albumCount ?? (mappedAlbums.isEmpty ? nil : mappedAlbums.count),
            )
        }
    }

    public func song(id: String) async throws -> SongResponse {
        try await perform(.song(id: id), cache: songCache) { (payload: SubsonicSongPayload) in
            guard let song = payload.song else {
                return SongResponse(href: nil, next: nil, data: [])
            }
            let mapped = Self.mapSong(
                song,
                artworkURL: self.artworkTemplateURL(coverArtID: song.coverArt),
            )
            return SongResponse(href: nil, next: nil, data: [mapped])
        }
    }

    public func playback(id: String) async throws -> PlaybackInfo {
        let cacheKey = "\(baseURL.absoluteString)|\(username)|\(SubsonicEndpoint.stream(id: id).cacheIdentifier)"
        if let fresh = await playbackCache.freshValue(forKey: cacheKey, ttl: cacheTTL) {
            return fresh
        }

        guard let rawSong = try await fetchSubsonicSong(id: id) else {
            throw APIError.invalidResponse
        }
        let song = Self.mapSong(rawSong, artworkURL: artworkTemplateURL(coverArtID: rawSong.coverArt))

        let info = try PlaybackInfo(
            playbackURL: makeURL(for: .stream(id: id)).absoluteString,
            size: rawSong.size ?? 0,
            title: song.attributes.name,
            artist: song.attributes.artistName,
            artistID: song.relationships?.artists?.data.first?.id ?? "",
            album: song.attributes.albumName ?? "",
            albumID: song.relationships?.albums?.data.first?.id ?? "",
            codec: rawSong.contentType ?? rawSong.suffix ?? "unknown",
        )
        await playbackCache.setValue(info, forKey: cacheKey)
        return info
    }

    public func lyrics(id: String) async throws -> LyricsResponse {
        try await perform(.lyrics(id: id), cache: lyricsCache) { (payload: SubsonicLyricsPayload) in
            LyricsResponse(lyrics: payload.text)
        }
    }

    private func perform<Response: Decodable, Output: Sendable>(
        _ endpoint: SubsonicEndpoint,
        cache: ResponseCache<Output>? = nil,
        decode: @escaping @Sendable (Response) async throws -> Output,
    ) async throws -> Output {
        guard baseURL.host != "example.com" else {
            throw APIError.transportFailed(
                message: String(localized: "No server configured.", bundle: .module),
            )
        }

        let cacheKey = "\(baseURL.absoluteString)|\(username)|\(endpoint.cacheIdentifier)"

        if let cache, let fresh = await cache.freshValue(forKey: cacheKey, ttl: cacheTTL) {
            return fresh
        }

        if cache != nil, let freshDiskData = await loadFreshDataFromDisk(forKey: cacheKey) {
            let decodedPayload = try decodeSubsonicResponse(Response.self, from: freshDiskData)
            let mapped = try await decode(decodedPayload)
            await cache?.setValue(mapped, forKey: cacheKey)
            return mapped
        }

        do {
            let initialAuthMode = currentAuthMode()
            let rawData: Data =
                if cache != nil {
                    try await fetchNetworkData(for: endpoint, authMode: initialAuthMode, coalescingKey: cacheKey)
                } else {
                    try await fetchNetworkData(for: endpoint, authMode: initialAuthMode, coalescingKey: nil)
                }

            let decodedPayload: Response
            do {
                decodedPayload = try decodeSubsonicResponse(Response.self, from: rawData)
            } catch {
                guard initialAuthMode == .token, shouldFallbackToPlainAuth(for: error) else {
                    throw error
                }

                updateAuthMode(.plain)
                let fallbackRawData = try await fetchNetworkData(
                    for: endpoint,
                    authMode: .plain,
                    coalescingKey: nil,
                )
                let fallbackPayload = try decodeSubsonicResponse(Response.self, from: fallbackRawData)
                let mapped = try await decode(fallbackPayload)
                if let cache {
                    await cache.setValue(mapped, forKey: cacheKey)
                    await storeToDisk(data: fallbackRawData, forKey: cacheKey)
                }
                return mapped
            }
            let mapped = try await decode(decodedPayload)
            if let cache {
                await cache.setValue(mapped, forKey: cacheKey)
                await storeToDisk(data: rawData, forKey: cacheKey)
            }
            return mapped
        } catch {
            if error is CancellationError {
                throw error
            }

            guard cache != nil, isFallbackEligible(error) else {
                throw error
            }

            try Task.checkCancellation()
            return try await staleFallback(
                forKey: cacheKey,
                cache: cache,
                originalError: error,
                responseType: Response.self,
                decode: decode,
            )
        }
    }

    private func fetchNetworkData(
        for endpoint: SubsonicEndpoint,
        authMode: SubsonicAuthenticationMode,
        coalescingKey: String?,
    ) async throws -> Data {
        let work: @Sendable () async throws -> Data = { [self] in
            let request = try urlRequest(for: endpoint, authMode: authMode)
            return try await Self.fetchRawData(session: session, request: request)
        }

        if let coalescingKey {
            return try await coalescer.perform(forKey: coalescingKey, work: work)
        } else {
            return try await work()
        }
    }

    private func decodeSubsonicResponse<Response: Decodable>(_ type: Response.Type, from data: Data) throws -> Response {
        do {
            let wrapped = try decoder.decode(SubsonicResponse<Response>.self, from: data)
            if wrapped.status == "ok", let payload = wrapped.payload {
                return payload
            }

            let error = wrapped.error
            throw APIError.subsonicRequestFailed(
                code: error?.code,
                message: error?.message ?? String(localized: "Unknown Subsonic error.", bundle: .module),
            )
        } catch let error as APIError {
            throw error
        } catch {
            let context = decodeContext(for: error)
            let host = baseURL.host ?? String(localized: "server", bundle: .module)
            let message = String(
                format: String(localized: "Failed to decode %@ from %@: %@", bundle: .module),
                locale: .current,
                String(describing: type),
                host,
                context,
            )
            throw APIError.decodingFailed(message: message)
        }
    }

    private func makeURL(for endpoint: SubsonicEndpoint) throws -> URL {
        try endpoint.url(baseURL: baseURL, authorization: authorization(mode: currentAuthMode()))
    }

    private func fetchSubsonicSong(id: String) async throws -> SubsonicSong? {
        try await perform(.song(id: id), cache: nil) { (payload: SubsonicSongPayload) in
            payload.song
        }
    }

    private func urlRequest(for endpoint: SubsonicEndpoint, authMode: SubsonicAuthenticationMode) throws -> URLRequest {
        let url = try endpoint.url(baseURL: baseURL, authorization: authorization(mode: authMode))
        return URLRequest(url: url)
    }

    private func authorization(mode: SubsonicAuthenticationMode) -> SubsonicAuthorization {
        SubsonicAuthorization(
            username: username,
            password: password,
            mode: mode,
            tokenSalt: tokenSalt,
        )
    }

    private func artworkTemplateURL(coverArtID: String?, baseURL: URL? = nil) -> String? {
        guard let coverArtID, coverArtID.isEmpty == false else {
            return nil
        }

        guard let url = try? SubsonicEndpoint.coverArt(id: coverArtID, size: nil)
            .url(baseURL: baseURL ?? self.baseURL, authorization: authorization(mode: currentAuthMode()))
        else {
            return nil
        }
        return url.absoluteString
    }

    private func currentAuthMode() -> SubsonicAuthenticationMode {
        authLock.withLock { authMode }
    }

    private func updateAuthMode(_ mode: SubsonicAuthenticationMode) {
        authLock.withLock {
            authMode = mode
        }
    }

    private func shouldFallbackToPlainAuth(for error: Error) -> Bool {
        switch error {
        case let APIError.subsonicRequestFailed(code, message):
            let text = message.lowercased()
            return code == 40
                || code == 41
                || text.contains("token")
                || text.contains("salt")
                || text.contains("password")
                || text.contains("authentication")
                || text.contains("credential")
        case let APIError.requestFailed(statusCode, _):
            return statusCode == 401 || statusCode == 403
        default:
            return false
        }
    }

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
            let serverMessage: String? = {
                guard
                    let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let message = json["error"] as? String
                else {
                    return nil
                }
                return message
            }()
            throw APIError.requestFailed(
                statusCode: httpResponse.statusCode,
                serverMessage: serverMessage,
            )
        }

        return data
    }

    private func loadFreshDataFromDisk(forKey key: String) async -> Data? {
        guard let provider = cacheStorageProvider,
              let envelope = await provider.load(forKey: key)
        else {
            return nil
        }

        guard envelope.version == cacheVersion else {
            await provider.remove(forKey: key)
            return nil
        }

        guard Date().timeIntervalSince(envelope.cachedAt) < cacheTTL else {
            return nil
        }

        return envelope.data
    }

    private func storeToDisk(data: Data, forKey key: String) async {
        guard let provider = cacheStorageProvider else {
            return
        }
        let envelope = CacheEnvelope(data: data, cachedAt: Date(), version: cacheVersion)
        await provider.store(envelope, forKey: key)
    }

    private func loadStaleDataFromDisk(forKey key: String) async -> Data? {
        guard let provider = cacheStorageProvider,
              let envelope = await provider.load(forKey: key)
        else {
            return nil
        }

        guard envelope.version == cacheVersion else {
            await provider.remove(forKey: key)
            return nil
        }

        return envelope.data
    }

    private func isFallbackEligible(_ error: Error) -> Bool {
        switch error {
        case APIError.transportFailed:
            true
        case let APIError.requestFailed(statusCode, _):
            (500 ... 599).contains(statusCode)
        default:
            false
        }
    }

    private func staleFallback<Response: Decodable, Output: Sendable>(
        forKey key: String,
        cache: ResponseCache<Output>?,
        originalError: Error,
        responseType: Response.Type,
        decode: @escaping @Sendable (Response) async throws -> Output,
    ) async throws -> Output {
        if let cache, let stale = await cache.staleValue(forKey: key) {
            try Task.checkCancellation()
            return stale
        }

        if let diskStaleData = await loadStaleDataFromDisk(forKey: key) {
            try Task.checkCancellation()
            let decodedPayload = try decodeSubsonicResponse(responseType, from: diskStaleData)
            let mapped = try await decode(decodedPayload)
            await cache?.setValue(mapped, forKey: key)
            return mapped
        }

        throw originalError
    }

    private func enrichSongSearchResponse(_ response: SearchResponse) async -> SearchResponse {
        guard let songs = response.results.songs, songs.data.isEmpty == false else {
            return response
        }

        let indexed = Array(songs.data.enumerated())
        let enrichedSongs = await withTaskGroup(of: (Int, CatalogSong).self, returning: [CatalogSong].self) { group in
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
                songs: ResourceList(href: songs.href, next: songs.next, data: enrichedSongs),
                albums: response.results.albums,
                artists: response.results.artists,
            ),
        )
    }

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

private extension SubsonicMusicService {
    static func mapSearchResponse(
        _ result: SubsonicSearchResult?,
        type: SearchType,
        limit: Int,
        offset: Int,
        artworkBuilder: (String?) -> String?,
    ) -> SearchResponse {
        let result = result ?? SubsonicSearchResult(songs: [], albums: [], artists: [])
        let nextOffset = offset + limit

        let songs: ResourceList<CatalogSong>? =
            if type == .song || result.songs.isEmpty == false {
                ResourceList(
                    href: nil,
                    next: result.songs.count >= limit ? "offset:\(nextOffset)" : nil,
                    data: result.songs.map { mapSong($0, artworkURL: artworkBuilder($0.coverArt)) },
                )
            } else {
                nil
            }

        let albums: ResourceList<CatalogAlbum>? =
            if type == .album || result.albums.isEmpty == false {
                ResourceList(
                    href: nil,
                    next: result.albums.count >= limit ? "offset:\(nextOffset)" : nil,
                    data: result.albums.map { mapAlbum($0, artworkURL: artworkBuilder($0.coverArt)) },
                )
            } else {
                nil
            }

        let artists: ResourceList<CatalogArtist>? =
            if type == .artist || result.artists.isEmpty == false {
                ResourceList(
                    href: nil,
                    next: result.artists.count >= limit ? "offset:\(nextOffset)" : nil,
                    data: result.artists.map {
                        mapArtist(
                            $0,
                            artworkURL: $0.artistImageUrl ?? artworkBuilder($0.coverArt),
                        )
                    },
                )
            } else {
                nil
            }

        return SearchResponse(results: SearchResults(songs: songs, albums: albums, artists: artists))
    }

    static func mapSong(_ song: SubsonicSong, artworkURL: String?) -> CatalogSong {
        let artist = mapArtistPlaceholder(id: song.artistId, name: song.artist, artworkURL: artworkURL)
        let album = mapAlbumPlaceholder(
            id: song.albumId,
            name: song.album,
            artistName: song.artist,
            artworkURL: artworkURL,
        )

        return CatalogSong(
            id: song.id,
            type: "songs",
            href: nil,
            attributes: CatalogSongAttributes(
                name: song.title,
                artistName: song.artist ?? "",
                albumName: song.album,
                url: song.contentType,
                durationInMillis: song.duration.map { $0 * 1000 },
                trackNumber: song.track,
                discNumber: song.discNumber,
                releaseDate: song.year.map(String.init),
                composerName: nil,
                hasLyrics: true,
                hasTimeSyncedLyrics: false,
                artwork: Artwork(width: nil, height: nil, url: artworkURL),
                playParams: CatalogPlayParams(
                    id: song.id,
                    kind: song.contentType ?? song.suffix ?? "song",
                ),
            ),
            relationships: CatalogSongRelationships(
                artists: artist.map { ResourceList(href: nil, next: nil, data: [$0]) },
                albums: album.map { ResourceList(href: nil, next: nil, data: [$0]) },
            ),
        )
    }

    static func mapAlbum(_ album: SubsonicAlbum, artworkURL: String?) -> CatalogAlbum {
        let artist = mapArtistPlaceholder(id: album.artistId, name: album.artist, artworkURL: artworkURL)
        let tracks = album.songs.map { mapSong($0, artworkURL: artworkURL) }

        return CatalogAlbum(
            id: album.id,
            type: "albums",
            href: nil,
            attributes: CatalogAlbumAttributes(
                artistName: album.artist ?? "",
                name: album.name,
                trackCount: album.songCount ?? tracks.count,
                releaseDate: album.year.map(String.init),
                genreNames: album.genre.map { [$0] },
                artwork: Artwork(width: nil, height: nil, url: artworkURL),
                playParams: CatalogPlayParams(id: album.id, kind: "album"),
            ),
            relationships: CatalogAlbumRelationships(
                artists: artist.map { ResourceList(href: nil, next: nil, data: [$0]) },
                tracks: tracks.isEmpty ? nil : ResourceList(href: nil, next: nil, data: tracks),
            ),
        )
    }

    static func mapArtist(_ artist: SubsonicArtist, artworkURL: String?) -> CatalogArtist {
        CatalogArtist(
            id: artist.id,
            type: "artists",
            href: nil,
            attributes: CatalogArtistAttributes(
                name: artist.name,
                artwork: Artwork(width: nil, height: nil, url: artworkURL),
            ),
        )
    }

    static func mapArtistPlaceholder(id: String?, name: String?, artworkURL: String?) -> CatalogArtist? {
        guard let id, let name, name.isEmpty == false else {
            return nil
        }
        return CatalogArtist(
            id: id,
            type: "artists",
            href: nil,
            attributes: CatalogArtistAttributes(
                name: name,
                artwork: Artwork(width: nil, height: nil, url: artworkURL),
            ),
        )
    }

    static func mapAlbumPlaceholder(id: String?, name: String?, artistName: String?, artworkURL: String?) -> CatalogAlbum? {
        guard let id, let name, name.isEmpty == false else {
            return nil
        }
        return CatalogAlbum(
            id: id,
            type: "albums",
            href: nil,
            attributes: CatalogAlbumAttributes(
                artistName: artistName ?? "",
                name: name,
                artwork: Artwork(width: nil, height: nil, url: artworkURL),
                playParams: CatalogPlayParams(id: id, kind: "album"),
            ),
            relationships: nil,
        )
    }
}

private struct SubsonicPingPayload: Decodable {}

extension KeyedDecodingContainer {
    func decodeLossyString(forKey key: Key) throws -> String {
        if let value = try? decode(String.self, forKey: key) {
            return value
        }
        if let value = try? decode(Int.self, forKey: key) {
            return String(value)
        }
        if let value = try? decode(Int64.self, forKey: key) {
            return String(value)
        }
        throw DecodingError.keyNotFound(key, .init(codingPath: codingPath, debugDescription: "Missing string-compatible value"))
    }

    func decodeLossyStringIfPresent(forKey key: Key) throws -> String? {
        if let value = try decodeIfPresent(String.self, forKey: key) {
            return value
        }
        if let value = try decodeIfPresent(Int.self, forKey: key) {
            return String(value)
        }
        if let value = try decodeIfPresent(Int64.self, forKey: key) {
            return String(value)
        }
        return nil
    }

    func decodeLossyIntIfPresent(forKey key: Key) throws -> Int? {
        if let value = try decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        if let value = try decodeIfPresent(String.self, forKey: key) {
            return Int(value)
        }
        return nil
    }

    func decodeLossyInt64IfPresent(forKey key: Key) throws -> Int64? {
        if let value = try decodeIfPresent(Int64.self, forKey: key) {
            return value
        }
        if let value = try decodeIfPresent(Int.self, forKey: key) {
            return Int64(value)
        }
        if let value = try decodeIfPresent(String.self, forKey: key) {
            return Int64(value)
        }
        return nil
    }
}
