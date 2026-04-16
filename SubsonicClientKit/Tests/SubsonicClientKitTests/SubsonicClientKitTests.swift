import Foundation
@testable import SubsonicClientKit
import Testing

private final class FixtureURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private enum FixtureServer {
    static let baseURL = URL(string: "https://unit-test.local/rest")!

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    static func wrappedResponse(payload: [String: Any], status: String = "ok") throws -> Data {
        let body = [
            "subsonic-response": [
                "status": status,
                "version": "1.16.1",
                "type": "wrapper-rs",
            ].merging(payload) { _, rhs in rhs },
        ]
        return try JSONSerialization.data(withJSONObject: body)
    }

    static func failedResponse(message: String, code: Int? = nil) throws -> Data {
        var error: [String: Any] = ["message": message]
        if let code {
            error["code"] = code
        }
        return try wrappedResponse(payload: ["error": error], status: "failed")
    }

    static func httpResponse(for request: URLRequest, statusCode: Int = 200) -> HTTPURLResponse {
        HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"],
        )!
    }

    static func searchPayload() -> [String: Any] {
        [
            "searchResult3": [
                "song": [
                    [
                        "id": "song-1",
                        "title": "Track One",
                        "album": "Album One",
                        "albumId": "album-1",
                        "artist": "Artist One",
                        "artistId": "artist-1",
                        "coverArt": "cover-song-1",
                        "duration": 213,
                        "track": 1,
                        "discNumber": 1,
                        "year": 2024,
                        "suffix": "m4a",
                        "contentType": "audio/m4a",
                        "size": 987_654,
                    ],
                ],
                "album": [
                    [
                        "id": "album-1",
                        "name": "Album One",
                        "artist": "Artist One",
                        "artistId": "artist-1",
                        "coverArt": "cover-album-1",
                        "songCount": 1,
                        "year": 2024,
                        "genre": "J-Pop",
                    ],
                ],
                "artist": [
                    [
                        "id": "artist-1",
                        "name": "Artist One",
                        "coverArt": "cover-artist-1",
                        "artistImageUrl": "https://cdn.example.com/search-artist-one.jpg",
                    ],
                ],
            ],
        ]
    }

    static func albumPayload() -> [String: Any] {
        [
            "album": [
                "id": "album-1",
                "name": "Album One",
                "artist": "Artist One",
                "artistId": "artist-1",
                "coverArt": "cover-album-1",
                "songCount": 2,
                "year": 2024,
                "genre": "J-Pop",
                "song": [
                    [
                        "id": "song-1",
                        "title": "Track One",
                        "album": "Album One",
                        "albumId": "album-1",
                        "artist": "Artist One",
                        "artistId": "artist-1",
                        "coverArt": "cover-song-1",
                        "duration": 213,
                        "track": 1,
                        "discNumber": 1,
                        "year": 2024,
                        "suffix": "m4a",
                        "contentType": "audio/m4a",
                        "size": 987_654,
                    ],
                    [
                        "id": "song-2",
                        "title": "Track Two",
                        "album": "Album One",
                        "albumId": "album-1",
                        "artist": "Artist One",
                        "artistId": "artist-1",
                        "coverArt": "cover-song-1",
                        "duration": 201,
                        "track": 2,
                        "discNumber": 1,
                        "year": 2024,
                        "suffix": "m4a",
                        "contentType": "audio/m4a",
                        "size": 876_543,
                    ],
                ],
            ],
        ]
    }

    static func songPayload() -> [String: Any] {
        [
            "song": [
                "id": "song-1",
                "title": "Track One",
                "album": "Album One",
                "albumId": "album-1",
                "artist": "Artist One",
                "artistId": "artist-1",
                "coverArt": "cover-song-1",
                "duration": 213,
                "track": 1,
                "discNumber": 1,
                "year": 2024,
                "suffix": "m4a",
                "contentType": "audio/m4a",
                "size": 987_654,
            ],
        ]
    }

    static func artistPayload() -> [String: Any] {
        [
            "artist": [
                "id": "artist-1",
                "name": "Artist One",
                "coverArt": "cover-artist-1",
                "artistImageUrl": "https://cdn.example.com/artist-one.jpg",
                "albumCount": 2,
                "album": [
                    [
                        "id": "album-1",
                        "name": "Album One",
                        "artist": "Artist One",
                        "artistId": "artist-1",
                        "coverArt": "cover-album-1",
                        "songCount": 1,
                        "year": 2024,
                        "genre": "J-Pop",
                    ],
                    [
                        "id": "album-2",
                        "name": "Album Two",
                        "artist": "Artist One",
                        "artistId": "artist-1",
                        "coverArt": "cover-album-2",
                        "songCount": 3,
                        "year": 2023,
                        "genre": "Pop",
                    ],
                ],
            ],
        ]
    }

    static func lyricsPayload() -> [String: Any] {
        [
            "lyrics": [
                "value": "[00:00.00]Track One\n[00:10.00]Line Two",
            ],
        ]
    }
}

@Suite(.serialized)
struct SubsonicMusicServiceTests {
    @Test
    func `search maps songs albums and artists`() async throws {
        FixtureURLProtocol.handler = { request in
            let data = try FixtureServer.wrappedResponse(payload: FixtureServer.searchPayload())
            return (FixtureServer.httpResponse(for: request), data)
        }

        let service = SubsonicMusicService(
            baseURL: FixtureServer.baseURL,
            username: "demo",
            password: "secret",
            session: FixtureServer.makeSession(),
        )

        let response = try await service.search(
            query: "track",
            type: .song,
            limit: 5,
            offset: 0,
            cacheSearchResponses: true,
            prefetchSongMetadata: false,
        )

        let song = try #require(response.results.songs?.data.first)
        #expect(song.id == "song-1")
        #expect(song.attributes.name == "Track One")
        #expect(song.relationships?.albums?.data.first?.id == "album-1")
        let artworkURL = try #require(song.attributes.artwork?.imageURL())
        #expect(artworkURL.absoluteString.contains("getCoverArt.view"))
        #expect(artworkURL.absoluteString.contains("size=%7Bw%7D") == false)

        let artist = try #require(response.results.artists?.data.first)
        #expect(artist.id == "artist-1")
        let artistArtworkURL = try #require(artist.attributes.artwork?.imageURL())
        #expect(artistArtworkURL.absoluteString == "https://cdn.example.com/search-artist-one.jpg")
    }

    @Test
    func `album maps track relationships`() async throws {
        FixtureURLProtocol.handler = { request in
            let data = try FixtureServer.wrappedResponse(payload: FixtureServer.albumPayload())
            return (FixtureServer.httpResponse(for: request), data)
        }

        let service = SubsonicMusicService(
            baseURL: FixtureServer.baseURL,
            username: "demo",
            password: "secret",
            session: FixtureServer.makeSession(),
        )

        let response = try await service.album(id: "album-1")
        let album = try #require(response.firstAlbum)
        #expect(album.attributes.name == "Album One")
        #expect(album.attributes.artistName == "Artist One")
        #expect(album.relationships?.tracks?.data.count == 2)
    }

    @Test
    func `artist maps nested albums`() async throws {
        FixtureURLProtocol.handler = { request in
            let data = try FixtureServer.wrappedResponse(payload: FixtureServer.artistPayload())
            return (FixtureServer.httpResponse(for: request), data)
        }

        let service = SubsonicMusicService(
            baseURL: FixtureServer.baseURL,
            username: "demo",
            password: "secret",
            session: FixtureServer.makeSession(),
        )

        let response = try #require(try await service.artist(id: "artist-1"))
        #expect(response.artist.id == "artist-1")
        #expect(response.artist.attributes.name == "Artist One")
        #expect(response.albumCount == 2)
        #expect(response.albums.count == 2)
        #expect(response.albums[0].id == "album-1")

        let artworkURL = try #require(response.artist.attributes.artwork?.imageURL())
        #expect(artworkURL.absoluteString == "https://cdn.example.com/artist-one.jpg")
    }

    @Test
    func `artwork imageURL removes encoded size placeholder`() throws {
        let artwork = Artwork(
            width: nil,
            height: nil,
            url: "https://example.com/rest/getCoverArt.view?id=cover-1&size=%7Bw%7D",
        )

        let url = try #require(artwork.imageURL(width: 88, height: 88))
        #expect(url.absoluteString == "https://example.com/rest/getCoverArt.view?id=cover-1")
    }

    @Test
    func `lyrics reads nested value payload`() async throws {
        FixtureURLProtocol.handler = { request in
            let data = try FixtureServer.wrappedResponse(payload: FixtureServer.lyricsPayload())
            return (FixtureServer.httpResponse(for: request), data)
        }

        let service = SubsonicMusicService(
            baseURL: FixtureServer.baseURL,
            username: "demo",
            password: "secret",
            session: FixtureServer.makeSession(),
        )

        let response = try await service.lyrics(id: "song-1")
        #expect(response.lyrics.contains("Line Two"))
    }

    @Test
    func `playback builds stream url with auth query and song metadata`() async throws {
        FixtureURLProtocol.handler = { request in
            let action = request.url?.lastPathComponent
            let payload: [String: Any]
            switch action {
            case "getSong.view":
                payload = FixtureServer.songPayload()
            case "ping.view":
                payload = [:]
            default:
                throw URLError(.unsupportedURL)
            }
            let data = try FixtureServer.wrappedResponse(payload: payload)
            return (FixtureServer.httpResponse(for: request), data)
        }

        let service = SubsonicMusicService(
            baseURL: FixtureServer.baseURL,
            username: "demo",
            password: "secret",
            session: FixtureServer.makeSession(),
        )

        let info = try await service.playback(id: "song-1")
        let components = try #require(URLComponents(string: info.playbackURL))
        let queryItems = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(components.path == "/rest/stream.view")
        #expect(queryItems["u"] == "demo")
        #expect(queryItems["t"]?.isEmpty == false)
        #expect(queryItems["s"]?.isEmpty == false)
        #expect(queryItems["id"] == "song-1")
        #expect(info.size == 987_654)
        #expect(info.codec == "audio/m4a")
        #expect(info.albumID == "album-1")
    }

    @Test
    func `token auth falls back to plain password`() async throws {
        var sawPlainPassword = false
        FixtureURLProtocol.handler = { request in
            let queryItems = Dictionary(uniqueKeysWithValues: (URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })

            if queryItems["t"]?.isEmpty == false {
                let data = try FixtureServer.failedResponse(message: "Token authentication unsupported", code: 40)
                return (FixtureServer.httpResponse(for: request), data)
            }

            if queryItems["p"] == "secret" {
                sawPlainPassword = true
                let data = try FixtureServer.wrappedResponse(payload: FixtureServer.songPayload())
                return (FixtureServer.httpResponse(for: request), data)
            }

            throw URLError(.userAuthenticationRequired)
        }

        let service = SubsonicMusicService(
            baseURL: FixtureServer.baseURL,
            username: "demo",
            password: "secret",
            session: FixtureServer.makeSession(),
        )

        let response = try await service.song(id: "song-1")
        #expect(response.firstSong?.id == "song-1")
        #expect(sawPlainPassword)
    }

    @Test
    func `subsonic business error surfaces as api error`() async throws {
        FixtureURLProtocol.handler = { request in
            let data = try FixtureServer.failedResponse(message: "missing song", code: 70)
            return (FixtureServer.httpResponse(for: request), data)
        }

        let service = SubsonicMusicService(
            baseURL: FixtureServer.baseURL,
            username: "demo",
            password: "secret",
            session: FixtureServer.makeSession(),
        )

        await #expect(throws: APIError.self) {
            try await service.song(id: "missing")
        }
    }
}
