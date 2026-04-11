//
//  APIClient.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import AmMusicKit
import ConfigurableKit
import Foundation

private struct APIClientConfiguration {
    let baseURL: URL
    let authorizationToken: String?
}

final class APIClient: @unchecked Sendable {
    private let cacheStorageProvider: (any CacheStorageProvider)?
    private let defaultBaseURL: URL
    private let session: URLSession
    private let stateLock = NSLock()

    private nonisolated(unsafe) var configuration: APIClientConfiguration
    private nonisolated(unsafe) var service: RemoteMusicService

    nonisolated var baseURL: URL {
        synchronizedState().baseURL
    }

    init(
        baseURL: URL,
        session: URLSession = .shared,
        cacheStorageProvider: (any CacheStorageProvider)? = nil,
    ) {
        defaultBaseURL = baseURL
        self.session = session
        self.cacheStorageProvider = cacheStorageProvider

        let configuration = Self.resolveConfiguration(defaultBaseURL: baseURL)
        self.configuration = configuration
        service = RemoteMusicService(
            baseURL: configuration.baseURL,
            session: session,
            cacheStorageProvider: cacheStorageProvider,
            authorizationToken: configuration.authorizationToken,
        )
    }

    nonisolated func performRequest(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }

    nonisolated func searchSongs(query: String, limit: Int, offset: Int) async throws -> [CatalogSong] {
        AppLog.verbose(self, "searchSongs query=\(query) limit=\(limit) offset=\(offset)")
        let service = synchronizedState().service
        do {
            let response = try await service.search(
                query: query,
                type: .song,
                limit: limit,
                offset: offset,
                cacheSearchResponses: true,
                prefetchSongMetadata: false,
            )
            let songs = response.results.songs?.data ?? []
            AppLog.info(self, "searchSongs returned \(songs.count) results")
            return songs
        } catch {
            AppLog.error(self, "searchSongs failed query=\(query) error=\(error)")
            throw error
        }
    }

    nonisolated func searchAlbums(query: String, limit: Int, offset: Int) async throws -> [CatalogAlbum] {
        AppLog.verbose(self, "searchAlbums query=\(query) limit=\(limit) offset=\(offset)")
        let service = synchronizedState().service
        do {
            let response = try await service.search(
                query: query,
                type: .album,
                limit: limit,
                offset: offset,
                cacheSearchResponses: true,
                prefetchSongMetadata: false,
            )
            let albums = response.results.albums?.data ?? []
            AppLog.info(self, "searchAlbums returned \(albums.count) results")
            return albums
        } catch {
            AppLog.error(self, "searchAlbums failed query=\(query) error=\(error)")
            throw error
        }
    }

    nonisolated func album(id: String) async throws -> CatalogAlbum? {
        AppLog.verbose(self, "album id=\(id)")
        do {
            let response = try await synchronizedState().service.album(id: id)
            AppLog.info(self, "album id=\(id) found=\(response.firstAlbum != nil)")
            return response.firstAlbum
        } catch {
            AppLog.error(self, "album failed id=\(id) error=\(error)")
            throw error
        }
    }

    nonisolated func song(id: String) async throws -> CatalogSong? {
        AppLog.verbose(self, "song id=\(id)")
        do {
            let response = try await synchronizedState().service.song(id: id)
            AppLog.info(self, "song id=\(id) found=\(response.firstSong != nil)")
            return response.firstSong
        } catch {
            AppLog.error(self, "song failed id=\(id) error=\(error)")
            throw error
        }
    }

    nonisolated func lyrics(id: String) async throws -> String {
        AppLog.verbose(self, "lyrics id=\(id)")
        do {
            let response = try await synchronizedState().service.lyrics(id: id)
            AppLog.info(self, "lyrics id=\(id) length=\(response.lyrics.count)")
            return response.lyrics
        } catch {
            AppLog.error(self, "lyrics failed id=\(id) error=\(error)")
            throw error
        }
    }

    nonisolated func playback(id: String) async throws -> PlaybackInfo {
        AppLog.verbose(self, "playback id=\(id)")
        let state = synchronizedState()
        do {
            var info = try await state.service.playback(id: id)
            if !info.playbackURL.hasPrefix("http") {
                let resolved = state.baseURL.appendingPathComponent(info.playbackURL)
                info = PlaybackInfo(
                    playbackURL: resolved.absoluteString,
                    size: info.size,
                    title: info.title,
                    artist: info.artist,
                    artistID: info.artistID,
                    album: info.album,
                    albumID: info.albumID,
                    codec: info.codec,
                )
            }
            AppLog.info(self, "playback id=\(id) codec=\(info.codec)")
            return info
        } catch {
            AppLog.error(self, "playback failed id=\(id) error=\(error)")
            throw error
        }
    }

    nonisolated func mediaURL(from rawURL: String?, width: Int, height: Int) -> URL? {
        Self.resolveMediaURL(rawURL, width: width, height: height, baseURL: baseURL)
    }

    nonisolated func downloadHTTPHeaders() -> [String: String] {
        let configuration = synchronizedConfiguration()
        return Self.downloadHTTPHeaders(authorizationToken: configuration.authorizationToken)
    }

    nonisolated func authorizationHeaders(for url: URL?) -> [String: String] {
        let configuration = synchronizedConfiguration()
        return Self.authorizationHeaders(
            for: url,
            baseURL: configuration.baseURL,
            authorizationToken: configuration.authorizationToken,
        )
    }

    nonisolated func authorizedRequest(_ request: URLRequest) -> URLRequest {
        let configuration = synchronizedConfiguration()
        return Self.authorizedRequest(
            request,
            baseURL: configuration.baseURL,
            authorizationToken: configuration.authorizationToken,
        )
    }

    nonisolated func invalidatePlaybackCache(id: String) async {
        let state = synchronizedState()
        let cacheKey = state.baseURL.appendingPathComponent("playback/\(id)").absoluteString
        await cacheStorageProvider?.remove(forKey: cacheKey)
        AppLog.info(self, "invalidatePlaybackCache id=\(id)")
    }

    nonisolated func clearResponseCache() async {
        AppLog.info(self, "clearResponseCache")
        let provider = stateLock.withLock {
            refreshConfigurationIfNeededLocked()
            rebuildServiceLocked()
            return cacheStorageProvider
        }

        await provider?.removeAll()
    }

    nonisolated static func downloadHTTPHeaders(authorizationToken: String?) -> [String: String] {
        guard let authorization = authorizationHeaderValue(from: authorizationToken) else {
            return [:]
        }
        return ["Authorization": authorization]
    }

    nonisolated static func authorizationHeaders(
        for url: URL?,
        baseURL: URL,
        authorizationToken: String?,
    ) -> [String: String] {
        guard let url, shouldAuthorize(url, baseURL: baseURL) else {
            return [:]
        }
        return downloadHTTPHeaders(authorizationToken: authorizationToken)
    }

    nonisolated static func authorizedRequest(
        _ request: URLRequest,
        baseURL: URL,
        authorizationToken: String?,
    ) -> URLRequest {
        guard let url = request.url else {
            return request
        }

        let headers = authorizationHeaders(
            for: url,
            baseURL: baseURL,
            authorizationToken: authorizationToken,
        )
        guard headers.isEmpty == false else {
            return request
        }

        var authorizedRequest = request
        for (field, value) in headers {
            authorizedRequest.setValue(value, forHTTPHeaderField: field)
        }
        return authorizedRequest
    }

    nonisolated static func resolveMediaURL(_ rawURL: String?, width: Int, height: Int, baseURL: URL? = nil) -> URL? {
        guard let rawURL, rawURL.isEmpty == false else {
            return nil
        }

        let resolved = rawURL
            .replacingOccurrences(of: "{w}", with: "\(width)")
            .replacingOccurrences(of: "{h}", with: "\(height)")

        if resolved.hasPrefix("//") {
            return URL(string: "https:" + resolved)
        }

        guard let url = URL(string: resolved) else {
            return nil
        }
        guard url.scheme == nil else {
            return url
        }
        guard let baseURL else {
            return nil
        }
        return URL(string: resolved, relativeTo: baseURL)?.absoluteURL
    }
}

private extension APIClient {
    nonisolated func synchronizedConfiguration() -> APIClientConfiguration {
        stateLock.withLock {
            refreshConfigurationIfNeededLocked()
            return configuration
        }
    }

    nonisolated func synchronizedState() -> (baseURL: URL, service: RemoteMusicService) {
        stateLock.withLock {
            refreshConfigurationIfNeededLocked()
            return (configuration.baseURL, service)
        }
    }

    nonisolated func refreshConfigurationIfNeededLocked() {
        let latestConfiguration = Self.resolveConfiguration(defaultBaseURL: defaultBaseURL)
        guard latestConfiguration.baseURL != configuration.baseURL
            || latestConfiguration.authorizationToken != configuration.authorizationToken
        else {
            return
        }

        configuration = latestConfiguration
        rebuildServiceLocked()
    }

    nonisolated func rebuildServiceLocked() {
        service = RemoteMusicService(
            baseURL: configuration.baseURL,
            session: session,
            cacheStorageProvider: cacheStorageProvider,
            authorizationToken: configuration.authorizationToken,
        )
    }

    nonisolated static func resolveConfiguration(defaultBaseURL: URL) -> APIClientConfiguration {
        let configuredHost = configuredAPIHost()
        let baseURL: URL = if let configuredHost,
                              let configuredURL = URL(string: "https://\(configuredHost)")
        {
            configuredURL
        } else {
            defaultBaseURL
        }

        return APIClientConfiguration(
            baseURL: baseURL,
            authorizationToken: configuredAuthorizationToken(),
        )
    }

    nonisolated static func configuredAPIHost() -> String? {
        let value: String = ConfigurableKit.value(forKey: AppPreferences.apiHostKey, defaultValue: "")
        return AppPreferences.normalizeHost(value)
    }

    nonisolated static func configuredAuthorizationToken() -> String? {
        let value: String = ConfigurableKit.value(
            forKey: AppPreferences.apiAuthorizationKey,
            defaultValue: "",
        )
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    nonisolated static func authorizationHeaderValue(from token: String?) -> String? {
        guard let token else {
            return nil
        }
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return nil
        }
        if trimmed.lowercased().hasPrefix("bearer ") {
            return trimmed
        }
        return "Bearer \(trimmed)"
    }

    nonisolated static func shouldAuthorize(_ url: URL, baseURL: URL) -> Bool {
        guard let requestHost = normalizedHost(from: url),
              let apiHost = normalizedHost(from: baseURL)
        else {
            return false
        }
        return requestHost.caseInsensitiveCompare(apiHost) == .orderedSame
    }

    nonisolated static func normalizedHost(from url: URL) -> String? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        if components.host == nil {
            components = URLComponents(url: url.absoluteURL, resolvingAgainstBaseURL: false) ?? components
        }
        return AppPreferences.normalizedHost(from: components)
    }
}
