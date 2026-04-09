@testable import AmMusicKit
import Foundation
import Testing

private final class FixtureURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            let response = try FixtureServer.response(for: request)
            client?.urlProtocol(self, didReceive: response.httpResponse, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: response.data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private enum FixtureServer {
    struct StubResponse {
        let httpResponse: HTTPURLResponse
        let data: Data
    }

    static let baseURL = URL(string: "https://unit-test.local")!
    static let testSongID = "1538259004"
    static let testSongAlbumID = "1538258997"
    static let testSongArtistID = "569972619"
    static let testAlbumID = "1480785880"
    static let testAlbumArtistID = "287018328"
    static let testAlbumTrackID = "1480785881"
    static let testPlaybackSize: Int64 = 22_960_666
    static let audioData = Data((0 ..< 4096).map { UInt8($0 % 251) })

    static func response(for request: URLRequest) throws -> StubResponse {
        guard let url = request.url else {
            throw APIError.invalidRequest
        }

        switch url.path {
        case "/search":
            return try jsonResponse(for: request, body: searchPayload(for: url))
        case "/album/\(testAlbumID)":
            return try jsonResponse(for: request, body: albumPayload())
        case "/song/\(testSongID)":
            return try jsonResponse(for: request, body: songPayload())
        case "/lyrics/\(testSongID)":
            return try jsonResponse(for: request, body: lyricsPayload())
        case "/playback/\(testSongID)":
            return try jsonResponse(for: request, body: playbackPayload())
        case "/cache/albums/\(testSongAlbumID)/\(testSongID).m4a":
            return mediaResponse(for: request, url: url)
        default:
            return emptyResponse(for: url, statusCode: 404)
        }
    }

    private static func jsonResponse(for request: URLRequest, body: Any) throws -> StubResponse {
        guard let url = request.url else {
            throw APIError.invalidRequest
        }

        let data = try JSONSerialization.data(withJSONObject: body)
        return StubResponse(
            httpResponse: HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!,
            data: data
        )
    }

    private static func mediaResponse(for request: URLRequest, url: URL) -> StubResponse {
        let fullLength = Int(testPlaybackSize)
        let rangeHeader = request.value(forHTTPHeaderField: "Range")

        if rangeHeader == "bytes=0-1023" {
            let partialData = audioData.subdata(in: 0 ..< 1024)
            return StubResponse(
                httpResponse: HTTPURLResponse(
                    url: url,
                    statusCode: 206,
                    httpVersion: nil,
                    headerFields: [
                        "Accept-Ranges": "bytes",
                        "Content-Length": "\(partialData.count)",
                        "Content-Range": "bytes 0-1023/\(fullLength)",
                        "Content-Type": "audio/mp4",
                    ]
                )!,
                data: partialData
            )
        }

        return StubResponse(
            httpResponse: HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: [
                    "Accept-Ranges": "bytes",
                    "Content-Length": "\(audioData.count)",
                    "Content-Type": "audio/mp4",
                ]
            )!,
            data: audioData
        )
    }

    private static func emptyResponse(for url: URL, statusCode: Int) -> StubResponse {
        StubResponse(
            httpResponse: HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!,
            data: Data()
        )
    }

    private static func searchPayload(for url: URL) -> [String: Any] {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []
        let searchType = queryItems.first(where: { $0.name == "type" })?.value

        let results: [String: Any] = switch searchType {
        case SearchType.album.rawValue:
            [
                "albums": resourceList(
                    href: "/v1/catalog/jp/search?l=ja&limit=1&offset=0&term=IOSYS&types=albums",
                    next: "/v1/catalog/jp/search?l=ja&offset=1&term=IOSYS&types=albums",
                    data: [albumResource(includeRelationships: false)]
                ),
            ]
        case SearchType.artist.rawValue:
            [
                "artists": resourceList(
                    href: "/v1/catalog/jp/search?l=ja&limit=1&offset=0&term=Aimer&types=artists",
                    next: "/v1/catalog/jp/search?l=ja&offset=1&term=Aimer&types=artists",
                    data: [songArtistResource()]
                ),
            ]
        default:
            [
                "songs": resourceList(
                    href: "/v1/catalog/jp/search?l=ja&limit=1&offset=0&term=Aimer&types=songs",
                    next: "/v1/catalog/jp/search?l=ja&offset=1&term=Aimer&types=songs",
                    data: [searchSongResource()]
                ),
            ]
        }

        return ["results": results]
    }

    private static func albumPayload() -> [String: Any] {
        [
            "href": "",
            "next": "",
            "data": [albumResource(includeRelationships: true)],
        ]
    }

    private static func songPayload() -> [String: Any] {
        [
            "href": "",
            "next": "",
            "data": [songDetailResource()],
        ]
    }

    private static func lyricsPayload() -> [String: Any] {
        [
            "lyrics": "[00:00.00]カタオモイ\n[00:10.00]君のような人に出会うまで",
        ]
    }

    private static func playbackPayload() -> [String: Any] {
        [
            "playbackUrl": "cache/albums/\(testSongAlbumID)/\(testSongID).m4a",
            "size": testPlaybackSize,
            "title": "カタオモイ",
            "artist": "Aimer",
            "artistId": testSongArtistID,
            "album": "daydream",
            "albumId": testSongAlbumID,
            "codec": "ALAC",
        ]
    }

    private static func resourceList(
        href: String,
        next: String? = nil,
        data: [[String: Any]]
    ) -> [String: Any] {
        var payload: [String: Any] = [
            "href": href,
            "data": data,
        ]
        if let next {
            payload["next"] = next
        }
        return payload
    }

    private static func emptyRelationship(href: String) -> [String: Any] {
        [
            "href": href,
            "data": NSNull(),
        ]
    }

    private static func songArtistResource() -> [String: Any] {
        [
            "id": testSongArtistID,
            "type": "artists",
            "href": "/v1/catalog/jp/artists/\(testSongArtistID)?l=ja",
            "attributes": [
                "name": "Aimer",
                "genreNames": ["J-Pop"],
                "url": "https://music.apple.com/jp/artist/aimer/\(testSongArtistID)",
            ],
        ]
    }

    private static func albumArtistResource() -> [String: Any] {
        [
            "id": testAlbumArtistID,
            "type": "artists",
            "href": "/v1/catalog/jp/artists/\(testAlbumArtistID)?l=ja",
            "attributes": [
                "name": "IOSYS",
                "artwork": [
                    "url": "https://is1-ssl.mzstatic.com/image/thumb/Music115/v4/4a/50/e7/4a50e746-5546-899b-269a-abd03753221c/4580547320640.jpg/{w}x{h}ac.jpg",
                ],
            ],
        ]
    }

    private static func artworkResource(
        width: Int,
        height: Int,
        url: String,
        bgColor: String,
        textColor1: String,
        textColor2: String,
        textColor3: String,
        textColor4: String
    ) -> [String: Any] {
        [
            "width": width,
            "height": height,
            "url": url,
            "bgColor": bgColor,
            "textColor1": textColor1,
            "textColor2": textColor2,
            "textColor3": textColor3,
            "textColor4": textColor4,
        ]
    }

    private static func searchSongResource() -> [String: Any] {
        var resource = songAttributesResource(
            id: testSongID,
            href: "/v1/catalog/jp/songs/\(testSongID)?l=ja",
            name: "カタオモイ",
            artistName: "Aimer",
            albumName: "daydream",
            artwork: artworkResource(
                width: 3000,
                height: 3000,
                url: "https://is1-ssl.mzstatic.com/image/thumb/Music116/v4/46/4a/84/464a843d-14cc-e5e2-a9d6-763eb558e104/4547366270358.jpg/{w}x{h}bb.jpg",
                bgColor: "fafbfc",
                textColor1: "090a0a",
                textColor2: "2d302c",
                textColor3: "393a3a",
                textColor4: "565955"
            ),
            durationInMillis: 207_360,
            trackNumber: 7,
            discNumber: 1,
            releaseDate: "2016-09-21",
            isrc: "JPU901602293",
            composerName: "内澤崇仁",
            audioTraits: ["atmos", "lossless", "lossy-stereo", "spatial"],
            genreNames: ["J-Pop", "ミュージック"],
            previewURL: "https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview211/v4/5a/6e/f1/5a6ef1d9-a5c8-d687-6e38-e9b17f5dfd26/mzaf_5272219760502350661.plus.aac.ep.m4a",
            extendedAssetURL: "",
            url: "https://music.apple.com/jp/album/%E3%82%AB%E3%82%BF%E3%82%AA%E3%83%A2%E3%82%A4/\(testSongAlbumID)?i=\(testSongID)",
            playParams: ["id": testSongID, "kind": "song"]
        )
        resource["relationships"] = [
            "artists": emptyRelationship(href: ""),
            "albums": emptyRelationship(href: ""),
        ]
        return resource
    }

    private static func albumResource(includeRelationships: Bool) -> [String: Any] {
        var resource: [String: Any] = [
            "id": testAlbumID,
            "type": "albums",
            "href": "/v1/catalog/jp/albums/\(testAlbumID)?l=ja",
            "attributes": [
                "artistName": "IOSYS",
                "name": "IOSYS音ゲーBEST!! ―東方アレンジ編―",
                "url": "https://music.apple.com/jp/album/iosys-otoge-best-toho-arrange-edition/\(testAlbumID)",
                "trackCount": 24,
                "releaseDate": "2016-01-31",
                "recordLabel": "東方同人音楽流通",
                "upc": "4580547320695",
                "copyright": "℗ 2016 IOSYS",
                "genreNames": ["J-Pop", "ミュージック"],
                "audioTraits": ["lossless", "lossy-stereo"],
                "contentRating": "",
                "isSingle": false,
                "isComplete": true,
                "isCompilation": true,
                "artwork": artworkResource(
                    width: 2500,
                    height: 2500,
                    url: "https://is1-ssl.mzstatic.com/image/thumb/Music113/v4/23/46/0e/23460e37-0689-b1a8-1963-e3aea217f0ed/4580547320695.jpg/{w}x{h}bb.jpg",
                    bgColor: "150100",
                    textColor1: "dad6e0",
                    textColor2: "c8b9b9",
                    textColor3: "b3abb3",
                    textColor4: "a49494"
                ),
                "playParams": [
                    "id": testAlbumID,
                    "kind": "album",
                ],
            ],
        ]

        if includeRelationships {
            resource["relationships"] = [
                "artists": resourceList(
                    href: "/v1/catalog/jp/albums/\(testAlbumID)/artists?l=ja",
                    data: [albumArtistResource()]
                ),
                "tracks": resourceList(
                    href: "/v1/catalog/jp/albums/\(testAlbumID)/tracks?l=ja",
                    next: "",
                    data: [albumTrackResource()]
                ),
            ]
        }

        return resource
    }

    private static func songDetailResource() -> [String: Any] {
        var resource = songAttributesResource(
            id: testSongID,
            href: "/v1/catalog/jp/songs/\(testSongID)?l=ja",
            name: "カタオモイ",
            artistName: "Aimer",
            albumName: "daydream",
            artwork: artworkResource(
                width: 3000,
                height: 3000,
                url: "https://is1-ssl.mzstatic.com/image/thumb/Music116/v4/46/4a/84/464a843d-14cc-e5e2-a9d6-763eb558e104/4547366270358.jpg/{w}x{h}bb.jpg",
                bgColor: "fafbfc",
                textColor1: "090a0a",
                textColor2: "2d302c",
                textColor3: "393a3a",
                textColor4: "565955"
            ),
            durationInMillis: 207_360,
            trackNumber: 7,
            discNumber: 1,
            releaseDate: "2016-09-21",
            isrc: "JPU901602293",
            composerName: "内澤崇仁",
            audioTraits: ["atmos", "lossless", "lossy-stereo", "spatial"],
            genreNames: ["J-Pop", "ミュージック"],
            previewURL: "https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview211/v4/5a/6e/f1/5a6ef1d9-a5c8-d687-6e38-e9b17f5dfd26/mzaf_5272219760502350661.plus.aac.ep.m4a",
            extendedAssetURL: "https://aod.itunes.apple.com/itunes-assets/HLSMusic221/v4/61/7a/2a/617a2a67-687b-b597-f202-58b5875f992a/P1238506890_default.m3u8",
            url: "https://music.apple.com/jp/album/%E3%82%AB%E3%82%BF%E3%82%AA%E3%83%A2%E3%82%A4/\(testSongAlbumID)?i=\(testSongID)",
            playParams: ["id": testSongID, "kind": "song"]
        )
        resource["relationships"] = [
            "artists": resourceList(
                href: "/v1/catalog/jp/songs/\(testSongID)/artists?l=ja",
                data: [songArtistResource()]
            ),
            "albums": resourceList(
                href: "/v1/catalog/jp/songs/\(testSongID)/albums?l=ja",
                data: [songAlbumResource()]
            ),
        ]
        return resource
    }

    private static func songAlbumResource() -> [String: Any] {
        [
            "id": testSongAlbumID,
            "type": "albums",
            "href": "/v1/catalog/jp/albums/\(testSongAlbumID)?l=ja",
            "attributes": [
                "artistName": "Aimer",
                "artwork": artworkResource(
                    width: 3000,
                    height: 3000,
                    url: "https://is1-ssl.mzstatic.com/image/thumb/Music116/v4/46/4a/84/464a843d-14cc-e5e2-a9d6-763eb558e104/4547366270358.jpg/{w}x{h}bb.jpg",
                    bgColor: "fafbfc",
                    textColor1: "090a0a",
                    textColor2: "2d302c",
                    textColor3: "393a3a",
                    textColor4: "565955"
                ),
                "genreNames": ["J-Pop", "ミュージック"],
                "isCompilation": false,
                "isComplete": true,
                "isMasteredForItunes": false,
                "isPrerelease": false,
                "isSingle": false,
                "name": "daydream",
                "playParams": [
                    "id": testSongAlbumID,
                    "kind": "album",
                ],
                "releaseDate": "2016-09-21",
                "trackCount": 13,
                "upc": "4547366270358",
                "url": "https://music.apple.com/jp/album/daydream/\(testSongAlbumID)",
            ],
        ]
    }

    private static func albumTrackResource() -> [String: Any] {
        var resource = songAttributesResource(
            id: testAlbumTrackID,
            href: "/v1/catalog/jp/songs/\(testAlbumTrackID)?l=ja",
            name: "魔理沙は大変なものを盗んでいきました",
            artistName: "IOSYS",
            albumName: "IOSYS音ゲーBEST!! ―東方アレンジ編―",
            artwork: artworkResource(
                width: 2500,
                height: 2500,
                url: "https://is1-ssl.mzstatic.com/image/thumb/Music113/v4/23/46/0e/23460e37-0689-b1a8-1963-e3aea217f0ed/4580547320695.jpg/{w}x{h}bb.jpg",
                bgColor: "150100",
                textColor1: "dad6e0",
                textColor2: "c8b9b9",
                textColor3: "b3abb3",
                textColor4: "a49494"
            ),
            durationInMillis: 242_274,
            trackNumber: 1,
            discNumber: 1,
            releaseDate: "2016-01-31",
            isrc: "JPI961900162",
            composerName: "ZUN & IOSYS",
            audioTraits: ["lossless", "lossy-stereo"],
            genreNames: ["J-Pop", "ミュージック"],
            previewURL: "https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/16/78/83/167883c9-98c7-e1e1-bc9d-779e55b3d5d7/mzaf_17080988409541719767.plus.aac.ep.m4a",
            extendedAssetURL: "https://aod.itunes.apple.com/itunes-assets/HLSMusic124/v4/c8/98/3a/c8983a53-7322-4c4c-f486-d73d8eecb349/P247941526_lossless.m3u8",
            url: "https://music.apple.com/jp/album/%E9%AD%94%E7%90%86%E6%B2%99%E3%81%AF%E5%A4%A7%E5%A4%89%E3%81%AA%E3%82%82%E3%81%AE%E3%82%92%E7%9B%97%E3%82%93%E3%81%A7%E3%81%84%E3%81%8D%E3%81%BE%E3%81%97%E3%81%9F/\(testAlbumID)?i=\(testAlbumTrackID)",
            playParams: ["id": testAlbumTrackID, "kind": "song"]
        )
        resource["relationships"] = [
            "artists": resourceList(
                href: "/v1/catalog/jp/songs/\(testAlbumTrackID)/artists?l=ja",
                data: [albumArtistResource()]
            ),
            "albums": emptyRelationship(href: ""),
        ]
        return resource
    }

    private static func songAttributesResource(
        id: String,
        href: String,
        name: String,
        artistName: String,
        albumName: String,
        artwork: [String: Any],
        durationInMillis: Int,
        trackNumber: Int,
        discNumber: Int,
        releaseDate: String,
        isrc: String,
        composerName: String,
        audioTraits: [String],
        genreNames: [String],
        previewURL: String,
        extendedAssetURL: String,
        url: String,
        playParams: [String: Any]
    ) -> [String: Any] {
        [
            "id": id,
            "type": "songs",
            "href": href,
            "attributes": [
                "name": name,
                "artistName": artistName,
                "albumName": albumName,
                "url": url,
                "durationInMillis": durationInMillis,
                "trackNumber": trackNumber,
                "discNumber": discNumber,
                "genreNames": genreNames,
                "hasLyrics": true,
                "hasTimeSyncedLyrics": true,
                "isMasteredForItunes": false,
                "isAppleDigitalMaster": false,
                "contentRating": "",
                "releaseDate": releaseDate,
                "extendedAssetUrls": [
                    "enhancedHls": extendedAssetURL,
                ],
                "isrc": isrc,
                "audioTraits": audioTraits,
                "audioLocale": "ja",
                "composerName": composerName,
                "previews": [
                    [
                        "url": previewURL,
                    ],
                ],
                "artwork": artwork,
                "playParams": playParams,
            ],
        ]
    }
}

private let testSongID = "1538259004" // Aimer - カタオモイ
private let testAlbumID = "1480785880" // IOSYS音ゲーBEST

private func makeFixtureSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [FixtureURLProtocol.self]
    return URLSession(configuration: config)
}

struct APIIntegrationTests {
    let session = makeFixtureSession()
    var service: RemoteMusicService {
        RemoteMusicService(baseURL: FixtureServer.baseURL, session: session)
    }

    // MARK: - Search

    @Test("Search songs returns results")
    func searchSongs() async throws {
        let response = try await service.search(
            query: "Aimer",
            type: .song,
            limit: 2,
            offset: 0,
            cacheSearchResponses: false,
            prefetchSongMetadata: false
        )

        let songs = try #require(response.results.songs)
        #expect(songs.data.isEmpty == false)

        let first = try #require(songs.data.first)
        #expect(first.id.isEmpty == false)
        #expect(first.type == "songs")
        #expect(first.attributes.name == "カタオモイ")
        #expect(first.attributes.artistName == "Aimer")
        #expect(first.relationships?.artists?.data.isEmpty == true)
        #expect(first.relationships?.albums?.data.isEmpty == true)
    }

    @Test("Search albums returns results")
    func searchAlbums() async throws {
        let response = try await service.search(
            query: "IOSYS",
            type: .album,
            limit: 1,
            offset: 0,
            cacheSearchResponses: false,
            prefetchSongMetadata: false
        )

        let albums = try #require(response.results.albums)
        #expect(albums.data.isEmpty == false)

        let first = try #require(albums.data.first)
        #expect(first.type == "albums")
        #expect(first.attributes.name == "IOSYS音ゲーBEST!! ―東方アレンジ編―")
        #expect(first.attributes.artistName == "IOSYS")
    }

    @Test("Search artists returns results")
    func searchArtists() async throws {
        let response = try await service.search(
            query: "Aimer",
            type: .artist,
            limit: 1,
            offset: 0,
            cacheSearchResponses: false,
            prefetchSongMetadata: false
        )

        let artists = try #require(response.results.artists)
        #expect(artists.data.isEmpty == false)

        let first = try #require(artists.data.first)
        #expect(first.type == "artists")
        #expect(first.attributes.name == "Aimer")
    }

    // MARK: - Album

    @Test("Fetch album by ID")
    func fetchAlbum() async throws {
        let response = try await service.album(id: testAlbumID)
        let album = try #require(response.firstAlbum)

        #expect(album.id == testAlbumID)
        #expect(album.attributes.name.isEmpty == false)
        #expect(album.attributes.artistName == "IOSYS")
        #expect(album.attributes.trackCount == 24)
        #expect(album.attributes.artwork != nil)
        #expect(album.attributes.artwork?.url?.contains("{w}") == true)

        let tracks = try #require(album.relationships?.tracks)
        #expect(tracks.data.isEmpty == false)

        let artists = try #require(album.relationships?.artists)
        #expect(artists.data.isEmpty == false)
    }

    // MARK: - Song

    @Test("Fetch song by ID")
    func fetchSong() async throws {
        let response = try await service.song(id: testSongID)
        let song = try #require(response.firstSong)

        #expect(song.id == testSongID)
        #expect(song.attributes.name == "カタオモイ")
        #expect(song.attributes.artistName == "Aimer")
        #expect(song.attributes.albumName == "daydream")
        #expect(song.attributes.durationInMillis != nil)
        #expect(song.attributes.trackNumber == 7)
        #expect(song.attributes.hasLyrics == true)
        #expect(song.attributes.hasTimeSyncedLyrics == true)
        #expect(song.attributes.artwork != nil)

        let artists = try #require(song.relationships?.artists)
        #expect(artists.data.isEmpty == false)
        let albums = try #require(song.relationships?.albums)
        #expect(albums.data.isEmpty == false)
    }

    // MARK: - Lyrics

    @Test("Fetch lyrics by song ID")
    func fetchLyrics() async throws {
        let response = try await service.lyrics(id: testSongID)

        #expect(response.lyrics.isEmpty == false)
        #expect(response.lyrics.contains("["))
    }

    // MARK: - Playback

    @Test("Fetch playback info by song ID")
    func fetchPlayback() async throws {
        let info = try await service.playback(id: testSongID)

        #expect(info.playbackURL.isEmpty == false)
        #expect(info.playbackURL.contains(".m4a"))
        #expect(info.size > 0)
        #expect(info.title == "カタオモイ")
        #expect(info.artist == "Aimer")
        #expect(info.album == "daydream")
        #expect(info.artistID == FixtureServer.testSongArtistID)
        #expect(info.albumID == FixtureServer.testSongAlbumID)
        #expect(info.codec == "ALAC")
        #expect(info.playbackURL == "cache/albums/\(FixtureServer.testSongAlbumID)/\(testSongID).m4a")
    }

    // MARK: - Playback URL Content-Range

    @Test("Playback URL supports HTTP Range requests")
    func playbackURLContentRange() async throws {
        let info = try await service.playback(id: testSongID)

        let fileURL = FixtureServer.baseURL.appendingPathComponent(info.playbackURL)
        var request = URLRequest(url: fileURL)
        request.setValue("bytes=0-1023", forHTTPHeaderField: "Range")

        let (data, response) = try await session.data(for: request)
        let httpResponse = try #require(response as? HTTPURLResponse)

        #expect(httpResponse.statusCode == 206)
        #expect(data.count == 1024)

        let contentRange = try #require(httpResponse.value(forHTTPHeaderField: "Content-Range"))
        #expect(contentRange.hasPrefix("bytes 0-1023/"))

        let acceptRanges = httpResponse.value(forHTTPHeaderField: "Accept-Ranges")
        #expect(acceptRanges == "bytes")
    }

    // MARK: - Artwork URL Resolution

    @Test("Artwork URL template resolves correctly")
    func artworkURLResolution() async throws {
        let response = try await service.album(id: testAlbumID)
        let album = try #require(response.firstAlbum)
        let artwork = try #require(album.attributes.artwork)

        let resolvedURL = try #require(artwork.imageURL(width: 600, height: 600))
        let urlString = resolvedURL.absoluteString

        #expect(urlString.contains("600x600"))
        #expect(urlString.contains("{w}") == false)
        #expect(urlString.contains("{h}") == false)
    }

    // MARK: - Error Handling

    @Test("Empty search query throws invalidRequest")
    func emptySearchQuery() async throws {
        await #expect(throws: APIError.self) {
            try await service.search(
                query: "   ",
                type: .song,
                limit: 1,
                offset: 0,
                cacheSearchResponses: false,
                prefetchSongMetadata: false
            )
        }
    }

    // MARK: - Storefront Parameter

    @Test("Song fetch with storefront parameter")
    func songWithStorefront() async throws {
        let response = try await service.song(id: testSongID, storefront: "jp")
        let song = try #require(response.firstSong)
        #expect(song.id == testSongID)
    }
}

struct ModelTests {
    @Test("SearchType raw values")
    func searchTypeRawValues() {
        #expect(SearchType.song.rawValue == "song")
        #expect(SearchType.album.rawValue == "album")
        #expect(SearchType.artist.rawValue == "artist")
    }

    @Test("SearchType titles")
    func searchTypeTitles() {
        #expect(SearchType.song.title == LocalizationTestSupport.currentLocalizedValue("Songs"))
        #expect(SearchType.album.title == LocalizationTestSupport.currentLocalizedValue("Albums"))
        #expect(SearchType.artist.title == LocalizationTestSupport.currentLocalizedValue("Artists"))
    }

    @Test("SearchType is CaseIterable")
    func searchTypeCaseIterable() {
        #expect(SearchType.allCases.count == 3)
    }

    @Test("Artwork imageURL with nil url returns nil")
    func artworkNilURL() {
        let artwork = Artwork(width: 100, height: 100, url: nil)
        #expect(artwork.imageURL() == nil)
    }

    @Test("Artwork imageURL with empty url returns nil")
    func artworkEmptyURL() {
        let artwork = Artwork(width: 100, height: 100, url: "")
        #expect(artwork.imageURL() == nil)
    }

    @Test("Artwork imageURL resolves template")
    func artworkTemplate() {
        let artwork = Artwork(width: 3000, height: 3000, url: "https://example.com/{w}x{h}bb.jpg")
        let resolved = artwork.imageURL(width: 500, height: 500)
        #expect(resolved?.absoluteString == "https://example.com/500x500bb.jpg")
    }

    @Test("PlaybackInfo decodes from snake_case JSON")
    func playbackInfoDecoding() throws {
        let json = """
        {
            "playbackUrl": "cache/albums/123/456.m4a",
            "size": 12345678,
            "title": "Test Song",
            "artist": "Test Artist",
            "artistId": "111",
            "album": "Test Album",
            "albumId": "222",
            "codec": "ALAC"
        }
        """
        let data = Data(json.utf8)
        let info = try JSONDecoder().decode(PlaybackInfo.self, from: data)

        #expect(info.playbackURL == "cache/albums/123/456.m4a")
        #expect(info.size == 12_345_678)
        #expect(info.title == "Test Song")
        #expect(info.artistID == "111")
        #expect(info.albumID == "222")
        #expect(info.codec == "ALAC")
    }

    @Test("ResourceList decodes missing data as empty array")
    func resourceListMissingData() throws {
        let json = """
        {"href": "/test", "next": null}
        """
        let data = Data(json.utf8)
        let list = try JSONDecoder().decode(ResourceList<CatalogSong>.self, from: data)

        #expect(list.href == "/test")
        #expect(list.next == nil)
        #expect(list.data.isEmpty)
    }

    @Test("CatalogSong equality uses id and type only")
    func songEquality() {
        let attrs = CatalogSongAttributes(name: "A", artistName: "B")
        let song1 = CatalogSong(id: "1", type: "songs", href: nil, attributes: attrs, relationships: nil)
        let song2 = CatalogSong(id: "1", type: "songs", href: "/different", attributes: attrs, relationships: nil)
        let song3 = CatalogSong(id: "2", type: "songs", href: nil, attributes: attrs, relationships: nil)

        #expect(song1 == song2)
        #expect(song1 != song3)
    }

    @Test("APIError descriptions")
    func apiErrorDescriptions() {
        #expect(APIError.invalidRequest.errorDescription != nil)
        #expect(APIError.invalidResponse.errorDescription != nil)
        #expect(APIError.requestFailed(statusCode: 404).errorDescription?.contains("404") == true)
        #expect(APIError.decodingFailed(message: "test").errorDescription == "test")
        #expect(APIError.transportFailed(message: "timeout").errorDescription == "timeout")
    }
}
