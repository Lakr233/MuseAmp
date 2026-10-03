import Foundation
@testable import MuseAmp
import MuseAmpDatabaseKit
import SubsonicClientKit
import Testing

@Suite(.serialized)
struct LyricsServiceTests {
    private func makeAPIClient() throws -> APIClient {
        try APIClient(baseURL: #require(URL(string: "https://example.com")))
    }

    @Test
    func `load falls back to the file's embedded lyrics and caches them`() async throws {
        let sandbox = TestLibrarySandbox()
        let database = try sandbox.makeDatabase()
        let store = LyricsCacheStore(paths: database.paths)
        let ingested = try await sandbox.ingestTrack(makeMockTrack(trackID: "1692905601"), into: database)
        let embeddedLyrics = "[00:01.00]Embedded one\n[00:05.00]Embedded two"
        try await embedLyrics(embeddedLyrics, into: ingested, paths: database.paths)
        try? store.removeLyrics(for: ingested.trackID)

        let service = try LyricsService(apiClient: makeAPIClient(), lyricsCacheStore: store, database: database)
        let lyrics = try await service.loadLyricsThrowing(for: ingested.trackID)

        #expect(lyrics == embeddedLyrics)
        #expect(store.lyrics(for: ingested.trackID) == embeddedLyrics)
    }

    @Test
    func `an earlier empty answer does not hide the file's embedded lyrics`() async throws {
        let sandbox = TestLibrarySandbox()
        let database = try sandbox.makeDatabase()
        let store = LyricsCacheStore(paths: database.paths)
        let ingested = try await sandbox.ingestTrack(makeMockTrack(trackID: "1692905602"), into: database)
        let embeddedLyrics = "[00:02.00]Embedded after empty"
        try await embedLyrics(embeddedLyrics, into: ingested, paths: database.paths)
        try store.saveLyrics("", for: ingested.trackID)

        let service = try LyricsService(apiClient: makeAPIClient(), lyricsCacheStore: store, database: database)
        let lyrics = try await service.loadLyricsThrowing(for: ingested.trackID)

        #expect(lyrics == embeddedLyrics)
        #expect(store.lyrics(for: ingested.trackID) == embeddedLyrics)
    }

    @Test
    func `without a server a song with no local lyrics has none, and nothing is remembered`() async throws {
        let sandbox = TestLibrarySandbox()
        let database = try sandbox.makeDatabase()
        let store = LyricsCacheStore(paths: database.paths)
        let apiClient = try makeAPIClient()
        let ingested = try await sandbox.ingestTrack(makeMockTrack(trackID: "1692905603"), into: database)
        try? store.removeLyrics(for: ingested.trackID)
        let service = LyricsService(apiClient: apiClient, lyricsCacheStore: store, database: database)

        let clock = ContinuousClock()
        let started = clock.now
        let lyrics = try await service.loadLyricsRetrying(for: ingested.trackID)

        #expect(!apiClient.hasConfiguredServer)
        #expect(lyrics.isEmpty)
        #expect(clock.now - started < .seconds(LyricsService.retryDelays[0]))
        #expect(!FileManager.default.fileExists(atPath: database.paths.lyricsCacheURL(for: ingested.trackID).path))
    }

    @Test
    func `a server answer of not found is remembered as no lyrics`() async throws {
        let sandbox = TestLibrarySandbox()
        let database = try sandbox.makeDatabase()
        let store = LyricsCacheStore(paths: database.paths)
        let ingested = try await sandbox.ingestTrack(makeMockTrack(trackID: "1692905604"), into: database)
        try? store.removeLyrics(for: ingested.trackID)
        let server = LyricsServerStub(trackIDs: [ingested.trackID], reply: LyricsServerStub.notFoundReply)
        let service = LyricsService(apiClient: server.makeAPIClient(), lyricsCacheStore: store, database: database)

        let first = try await service.loadLyricsRetrying(for: ingested.trackID)
        let second = try await service.loadLyricsRetrying(for: ingested.trackID)

        #expect(first.isEmpty)
        #expect(second.isEmpty)
        #expect(store.lyrics(for: ingested.trackID) == "")
        #expect(server.requestCount == 1)
    }

    @Test
    func `a bare HTTP 404 shows no lyrics but is asked again next time`() async throws {
        let sandbox = TestLibrarySandbox()
        let database = try sandbox.makeDatabase()
        let store = LyricsCacheStore(paths: database.paths)
        let ingested = try await sandbox.ingestTrack(makeMockTrack(trackID: "1692905605"), into: database)
        try? store.removeLyrics(for: ingested.trackID)
        let server = LyricsServerStub(trackIDs: [ingested.trackID], reply: "{}", statusCode: 404)
        let service = LyricsService(apiClient: server.makeAPIClient(), lyricsCacheStore: store, database: database)

        let first = try await service.loadLyricsRetrying(for: ingested.trackID)
        #expect(first.isEmpty)
        #expect(store.lyrics(for: ingested.trackID) == nil)

        let lyrics = "[00:01.00]Back after the outage"
        try server.setReply(LyricsServerStub.lyricsReply(lyrics))
        server.setStatusCode(200)
        let second = try await service.loadLyricsRetrying(for: ingested.trackID)

        #expect(second == lyrics)
        #expect(store.lyrics(for: ingested.trackID) == lyrics)
        #expect(server.requestCount == 2)
    }

    @Test
    func `only a not found answer means the server has no lyrics`() {
        #expect(LyricsService.isNoLyricsAnswer(APIError.subsonicRequestFailed(code: 70, message: "Song not found")))
        #expect(LyricsService.isNoLyricsAnswer(APIError.subsonicRequestFailed(code: nil, message: "apple api request failed: 404 Not Found")))
        #expect(LyricsService.isNoLyricsAnswer(APIError.subsonicRequestFailed(code: 0, message: "Lyrics not found")))
        #expect(!LyricsService.isNoLyricsAnswer(APIError.requestFailed(statusCode: 404, serverMessage: nil)))
        #expect(LyricsService.isEndpointNotFound(APIError.requestFailed(statusCode: 404, serverMessage: nil)))
        #expect(!LyricsService.isEndpointNotFound(APIError.subsonicRequestFailed(code: 70, message: "Song not found")))
        #expect(!LyricsService.isNoLyricsAnswer(APIError.subsonicRequestFailed(code: 40, message: "User not found")))
        #expect(!LyricsService.isNoLyricsAnswer(APIError.subsonicRequestFailed(code: 50, message: "Not authorized")))
        #expect(!LyricsService.isNoLyricsAnswer(APIError.subsonicRequestFailed(code: 0, message: "upstream timed out")))
        #expect(!LyricsService.isNoLyricsAnswer(APIError.requestFailed(statusCode: 500, serverMessage: nil)))
        #expect(!LyricsService.isNoLyricsAnswer(APIError.transportFailed(message: "offline")))
        #expect(!LyricsService.isNoLyricsAnswer(APIError.decodingFailed(message: "bad")))
    }

    @Test
    func `only failures that can clear up on their own are transient`() {
        #expect(LyricsService.isTransientFetchError(APIError.transportFailed(message: "offline")))
        #expect(LyricsService.isTransientFetchError(APIError.requestFailed(statusCode: 503, serverMessage: nil)))
        #expect(LyricsService.isTransientFetchError(APIError.requestFailed(statusCode: 429, serverMessage: nil)))
        #expect(!LyricsService.isTransientFetchError(APIError.requestFailed(statusCode: 404, serverMessage: nil)))
        #expect(!LyricsService.isTransientFetchError(APIError.subsonicRequestFailed(code: 70, message: "Not found")))
        #expect(!LyricsService.isTransientFetchError(APIError.decodingFailed(message: "bad")))
        #expect(!LyricsService.isTransientFetchError(CancellationError()))
    }
}

func embedLyrics(_ lyrics: String, into track: AudioTrackRecord, paths: LibraryPaths) async throws {
    try await ExportMetadataProcessor.embedExportMetadata(
        ExportMetadataProcessor.ExportInfo(
            trackID: track.trackID,
            albumID: track.albumID,
            artworkURL: nil,
            lyrics: lyrics,
            title: track.title,
            artistName: track.artistName,
            albumName: track.albumTitle,
        ),
        into: paths.absoluteAudioURL(for: track.relativePath),
    )
}
