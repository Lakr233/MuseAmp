//
//  APIClient.swift
//  MuseAmp
//
//  Created by @Lakr233 on 2026/04/11.
//

import SubsonicClientKit
#if canImport(ConfigurableKit)
    import ConfigurableKit
#endif
import Foundation

private struct APIClientConfiguration {
    let baseURL: URL
    let username: String
    let password: String
}

final class APIClient: @unchecked Sendable {
    private let defaultBaseURL: URL
    private let session: URLSession
    private let stateLock = NSLock()

    private nonisolated(unsafe) var configuration: APIClientConfiguration
    private nonisolated(unsafe) var service: SubsonicMusicService

    nonisolated var baseURL: URL {
        synchronizedState().baseURL
    }

    init(
        baseURL: URL,
        session: URLSession = .shared,
    ) {
        defaultBaseURL = baseURL
        self.session = session

        let configuration = Self.resolveConfiguration(defaultBaseURL: baseURL)
        self.configuration = configuration
        service = SubsonicMusicService(
            baseURL: configuration.baseURL,
            username: configuration.username,
            password: configuration.password,
            session: session,
        )
    }

    nonisolated func performRequest(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }

    nonisolated func ping() async throws {
        AppLog.verbose(self, "ping baseURL=\(baseURL.absoluteString)")
        do {
            try await synchronizedState().service.ping()
            AppLog.info(self, "ping succeeded")
        } catch {
            AppLog.error(self, "ping failed error=\(error)")
            throw error
        }
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

    nonisolated func searchArtists(query: String, limit: Int, offset: Int) async throws -> [CatalogArtist] {
        AppLog.verbose(self, "searchArtists query=\(query) limit=\(limit) offset=\(offset)")
        let service = synchronizedState().service
        do {
            let response = try await service.search(
                query: query,
                type: .artist,
                limit: limit,
                offset: offset,
                cacheSearchResponses: true,
                prefetchSongMetadata: false,
            )
            let artists = response.results.artists?.data ?? []
            AppLog.info(self, "searchArtists returned \(artists.count) results")
            return artists
        } catch {
            AppLog.error(self, "searchArtists failed query=\(query) error=\(error)")
            throw error
        }
    }

    nonisolated func artist(id: String) async throws -> ArtistResponse? {
        AppLog.verbose(self, "artist id=\(id)")
        do {
            let response = try await synchronizedState().service.artist(id: id)
            AppLog.info(self, "artist id=\(id) found=\(response != nil)")
            return response
        } catch {
            AppLog.error(self, "artist failed id=\(id) error=\(error)")
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

    nonisolated static func resolveMediaURL(_ rawURL: String?, width: Int, height: Int, baseURL: URL? = nil) -> URL? {
        guard let rawURL, rawURL.isEmpty == false else {
            return nil
        }

        let resolved = Artwork.resolvedURLString(
            from: rawURL,
            width: width,
            height: height,
        )

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
    nonisolated func synchronizedState() -> (baseURL: URL, service: SubsonicMusicService) {
        stateLock.withLock {
            refreshConfigurationIfNeededLocked()
            return (configuration.baseURL, service)
        }
    }

    nonisolated func refreshConfigurationIfNeededLocked() {
        let latestConfiguration = Self.resolveConfiguration(defaultBaseURL: defaultBaseURL)
        guard latestConfiguration.baseURL != configuration.baseURL
            || latestConfiguration.username != configuration.username
            || latestConfiguration.password != configuration.password
        else {
            return
        }

        configuration = latestConfiguration
        rebuildServiceLocked()
    }

    nonisolated func rebuildServiceLocked() {
        service = SubsonicMusicService(
            baseURL: configuration.baseURL,
            username: configuration.username,
            password: configuration.password,
            session: session,
        )
    }

    nonisolated static func resolveConfiguration(defaultBaseURL: URL) -> APIClientConfiguration {
        let configured = AppPreferences.currentSubsonicConfiguration
        return APIClientConfiguration(
            baseURL: configured?.baseURL ?? defaultBaseURL,
            username: configured?.username ?? "",
            password: configured?.password ?? "",
        )
    }
}
