@testable import AmMusic
import AmMusicDatabaseKit
import Foundation
import Testing

@Suite(.serialized)
struct DownloadSyncTests {
    // MARK: - APIClient download headers

    @Test("download headers include bearer authorization")
    func apiClientDownloadHeadersIncludeAuthorization() {
        let headers = APIClient.downloadHTTPHeaders(authorizationToken: "test-token")
        #expect(headers["Authorization"] == "Bearer test-token")
    }

    @Test("download headers preserve existing bearer prefix")
    func apiClientDownloadHeadersPreserveBearerPrefix() {
        let headers = APIClient.downloadHTTPHeaders(authorizationToken: "Bearer already-prefixed")
        #expect(headers["Authorization"] == "Bearer already-prefixed")
    }

    @Test("download headers omit empty authorization")
    func apiClientDownloadHeadersOmitEmptyAuthorization() {
        let headers = APIClient.downloadHTTPHeaders(authorizationToken: "   ")
        #expect(headers.isEmpty)
    }

    @Test("authorized request adds authorization for matching API host")
    func apiClientAuthorizedRequestForAPIHost() throws {
        let request = try URLRequest(url: #require(URL(string: "https://example.com/song/1")))
        let authorizedRequest = try APIClient.authorizedRequest(
            request,
            baseURL: #require(URL(string: "https://example.com")),
            authorizationToken: "test-token"
        )
        #expect(authorizedRequest.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
    }

    @Test("authorized request skips authorization for external host")
    func apiClientAuthorizedRequestForExternalHost() throws {
        let request = try URLRequest(url: #require(URL(string: "https://cdn.example.net/song/1")))
        let authorizedRequest = try APIClient.authorizedRequest(
            request,
            baseURL: #require(URL(string: "https://example.com")),
            authorizationToken: "test-token"
        )
        #expect(authorizedRequest.value(forHTTPHeaderField: "Authorization") == nil)
    }

    // MARK: - PlaylistEntry metadata persistence

    @Test("PlaylistEntry full metadata round-trips through database")
    func playlistEntryMetadataPersistence() async throws {
        let sandbox = TestLibrarySandbox()
        let database = try sandbox.makeDatabase()
        let playlist = try await database.createPlaylist(name: "Test")

        let entry = PlaylistEntry(
            trackID: "track-1",
            title: "Song 1",
            artistName: "Artist",
            albumID: "album-42",
            albumTitle: "My Album",
            artworkURL: "https://example.com/art.jpg",
            durationMillis: 240_000,
            trackNumber: 3,
            lyrics: "Hello world"
        )
        try await database.addEntry(entry, to: playlist.id)

        let playlistRecord = try database.fetchPlaylist(id: playlist.id)
        let fetched = try #require(playlistRecord)
        let fetchedEntry = try #require(fetched.entries.first)
        #expect(fetchedEntry.albumID == "album-42")
        #expect(fetchedEntry.albumTitle == "My Album")
        #expect(fetchedEntry.durationMillis == 240_000)
        #expect(fetchedEntry.trackNumber == 3)
        #expect(fetchedEntry.lyrics == "Hello world")
    }

    @Test("PlaylistEntry nil optional fields round-trip correctly")
    func playlistEntryNilFields() async throws {
        let sandbox = TestLibrarySandbox()
        let database = try sandbox.makeDatabase()
        let playlist = try await database.createPlaylist(name: "Test")

        let entry = PlaylistEntry(
            trackID: "track-2",
            title: "Song 2",
            artistName: "Artist",
            artworkURL: nil
        )
        try await database.addEntry(entry, to: playlist.id)

        let playlistRecord = try database.fetchPlaylist(id: playlist.id)
        let fetched = try #require(playlistRecord)
        let fetchedEntry = try #require(fetched.entries.first)
        #expect(fetchedEntry.albumID == nil)
        #expect(fetchedEntry.albumTitle == nil)
        #expect(fetchedEntry.durationMillis == nil)
        #expect(fetchedEntry.trackNumber == nil)
        #expect(fetchedEntry.lyrics == nil)
    }

    // MARK: - updateSongLyrics

    @Test("updateSongLyrics updates lyrics for matching track")
    func updateSongLyrics() async throws {
        let sandbox = TestLibrarySandbox()
        let database = try sandbox.makeDatabase()
        let playlist = try await database.createPlaylist(name: "Lyrics Test")

        let entry = PlaylistEntry(trackID: "t1", title: "Song", artistName: "A", artworkURL: nil)
        try await database.addEntry(entry, to: playlist.id)

        try await database.updateSongLyrics("New lyrics here", trackID: "t1", playlistID: playlist.id)

        let playlistRecord = try database.fetchPlaylist(id: playlist.id)
        let fetched = try #require(playlistRecord)
        #expect(fetched.entries.first?.lyrics == "New lyrics here")
    }

    @Test("updateSongLyrics does nothing for non-matching track")
    func updateSongLyricsNoMatch() async throws {
        let sandbox = TestLibrarySandbox()
        let database = try sandbox.makeDatabase()
        let playlist = try await database.createPlaylist(name: "Lyrics Test")

        let entry = PlaylistEntry(trackID: "t1", title: "Song", artistName: "A", artworkURL: nil)
        try await database.addEntry(entry, to: playlist.id)

        try await database.updateSongLyrics("Lyrics", trackID: "nonexistent", playlistID: playlist.id)

        let playlistRecord = try database.fetchPlaylist(id: playlist.id)
        let fetched = try #require(playlistRecord)
        #expect(fetched.entries.first?.lyrics == nil)
    }

    // MARK: - PlaylistStore.addSong callback

    @Test("PlaylistStore.addSong fires onSongAdded for new songs")
    func addSongFiresCallback() throws {
        let sandbox = TestLibrarySandbox()
        let database = try sandbox.makeDatabase()
        let store = PlaylistStore(database: database)
        let playlist = store.createPlaylist(name: "Callback Test")

        var receivedEntries: [PlaylistEntry] = []
        store.onSongAdded = { entry in
            receivedEntries.append(entry)
        }

        let entry = PlaylistEntry(trackID: "s1", title: "Song", artistName: "A", artworkURL: nil)
        let inserted = store.addSong(entry, to: playlist.id)

        #expect(inserted == true)
        #expect(receivedEntries.count == 1)
        #expect(receivedEntries.first?.trackID == "s1")
    }

    @Test("PlaylistStore.addSong fires callback for duplicate playlist entries")
    func addSongFiresCallbackForDuplicateEntry() throws {
        let sandbox = TestLibrarySandbox()
        let database = try sandbox.makeDatabase()
        let store = PlaylistStore(database: database)
        let playlist = store.createPlaylist(name: "Dup Test")

        let entry = PlaylistEntry(trackID: "s1", title: "Song", artistName: "A", artworkURL: nil)
        store.addSong(entry, to: playlist.id)

        var callCount = 0
        store.onSongAdded = { _ in callCount += 1 }
        let inserted = store.addSong(entry, to: playlist.id)

        #expect(inserted == true)
        #expect(callCount == 1)
        #expect(store.playlist(for: playlist.id)?.songs.count == 2)
    }
}
