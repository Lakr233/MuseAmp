@testable import AmMusic
import AmMusicDatabaseKit
import Foundation
import Testing

@Suite(.serialized)
@MainActor
struct PlaylistStoreTests {
    private func makeTempStore() throws -> (TestLibrarySandbox, PlaylistStore) {
        let sandbox = TestLibrarySandbox()
        let database = try sandbox.makeDatabase()
        let store = PlaylistStore(database: database)
        return (sandbox, store)
    }

    @Test("Create playlist adds to store")
    func createPlaylist() throws {
        let (_, store) = try makeTempStore()
        let playlist = store.createPlaylist(name: "My Playlist")

        #expect(store.playlists.count == 1)
        #expect(playlist.name == "My Playlist")
        #expect(playlist.songs.isEmpty)
    }

    @Test("Delete playlist removes from store")
    func deletePlaylist() throws {
        let (_, store) = try makeTempStore()
        let playlist = store.createPlaylist(name: "To Delete")
        store.deletePlaylist(id: playlist.id)

        #expect(store.playlists.isEmpty)
    }

    @Test("Delete playlists removes selected playlists from store")
    func deletePlaylists() throws {
        let (_, store) = try makeTempStore()
        let first = store.createPlaylist(name: "First")
        _ = store.createPlaylist(name: "Second")
        let third = store.createPlaylist(name: "Third")

        store.deletePlaylists(ids: [first.id, third.id])

        #expect(store.playlists.count == 1)
        #expect(store.playlists.first?.name == "Second")
    }

    @Test("Rename playlist updates name")
    func renamePlaylist() throws {
        let (_, store) = try makeTempStore()
        let playlist = store.createPlaylist(name: "Old Name")
        store.renamePlaylist(id: playlist.id, name: "New Name")

        #expect(store.playlists.first?.name == "New Name")
    }

    @Test("Add song to playlist")
    func addSong() throws {
        let (_, store) = try makeTempStore()
        let playlist = store.createPlaylist(name: "Songs")
        let song = PlaylistEntry(trackID: "123", title: "Test Song", artistName: "Artist", artworkURL: nil)

        store.addSong(song, to: playlist.id)

        #expect(store.playlist(for: playlist.id)?.songs.count == 1)
        #expect(store.playlist(for: playlist.id)?.songs.first?.title == "Test Song")
    }

    @Test("Adding duplicate song creates another playlist entry")
    func addDuplicateSongCreatesAnotherEntry() throws {
        let (_, store) = try makeTempStore()
        let playlist = store.createPlaylist(name: "Songs")
        let song = PlaylistEntry(trackID: "123", title: "Test Song", artistName: "Artist", artworkURL: nil)

        store.addSong(song, to: playlist.id)
        store.addSong(song, to: playlist.id)

        #expect(store.playlist(for: playlist.id)?.songs.count == 2)
        #expect(store.playlist(for: playlist.id)?.songs.map(\.trackID) == ["123", "123"])
    }

    @Test("Remove song from playlist")
    func removeSong() throws {
        let (_, store) = try makeTempStore()
        let playlist = store.createPlaylist(name: "Songs")
        let song = PlaylistEntry(trackID: "123", title: "Test", artistName: "A", artworkURL: nil)
        store.addSong(song, to: playlist.id)

        store.removeSong(at: 0, from: playlist.id)

        #expect(store.playlist(for: playlist.id)?.songs.isEmpty == true)
    }

    @Test("Move song reorders playlist")
    func moveSong() throws {
        let (_, store) = try makeTempStore()
        let playlist = store.createPlaylist(name: "Songs")
        store.addSong(PlaylistEntry(trackID: "1", title: "A", artistName: "X", artworkURL: nil), to: playlist.id)
        store.addSong(PlaylistEntry(trackID: "2", title: "B", artistName: "X", artworkURL: nil), to: playlist.id)
        store.addSong(PlaylistEntry(trackID: "3", title: "C", artistName: "X", artworkURL: nil), to: playlist.id)

        store.moveSong(in: playlist.id, from: 2, to: 0)

        let names = store.playlist(for: playlist.id)?.songs.map(\.title)
        #expect(names == ["C", "A", "B"])
    }

    @Test("Persistence round-trip preserves data")
    func persistenceRoundTrip() throws {
        let sandbox = TestLibrarySandbox()
        let database = try sandbox.makeDatabase()

        let store1 = PlaylistStore(database: database)
        let playlist = store1.createPlaylist(name: "Persisted")
        store1.addSong(
            PlaylistEntry(trackID: "42", title: "Saved Song", artistName: "Saved Artist", artworkURL: nil),
            to: playlist.id
        )

        let store2 = PlaylistStore(database: database)
        #expect(store2.playlists.count == 1)
        #expect(store2.playlists.first?.name == "Persisted")
        #expect(store2.playlists.first?.songs.first?.title == "Saved Song")
    }

    @Test("Legacy playlist migration tolerates sparse JSON")
    func migrateSparseLegacyPlaylists() throws {
        let sandbox = TestLibrarySandbox()
        let database = try sandbox.makeDatabase()
        let legacyFileURL = sandbox.baseDirectory.appendingPathComponent("playlists.json")

        let payload = """
        [
          {
            "name": "Migrated Playlist",
            "songs": [
              {
                "id": "track-42",
                "name": "Saved Song",
                "artistName": "Saved Artist"
              }
            ]
          }
        ]
        """
        try Data(payload.utf8).write(to: legacyFileURL)

        let store = PlaylistStore(database: database, legacyFileURL: legacyFileURL)
        #expect(store.playlists.count == 1)
        #expect(store.playlists.first?.name == "Migrated Playlist")
        #expect(store.playlists.first?.songs.first?.trackID == "track-42")
        #expect(store.playlists.first?.songs.first?.artistName == "Saved Artist")
        #expect(FileManager.default.fileExists(atPath: legacyFileURL.appendingPathExtension("migrated").path))
    }

    @Test("Liked toggle auto-creates liked playlist")
    func likedToggleAutoCreatesPlaylist() throws {
        let (_, store) = try makeTempStore()
        let song = PlaylistEntry(trackID: "liked-track", title: "Liked Track", artistName: "Artist", artworkURL: nil)

        #expect(store.likedSongsPlaylist() == nil)
        #expect(store.isLiked(trackID: song.trackID) == false)
        #expect(store.toggleLiked(song) == .liked)
        #expect(store.isLiked(trackID: song.trackID) == true)

        let playlist = store.likedSongsPlaylist()
        #expect(playlist?.id == Playlist.likedSongsPlaylistID)
        #expect(playlist?.name == String(localized: "Liked Songs"))
        #expect(playlist?.coverImageData != nil)
        #expect(playlist?.songs.map(\.trackID) == [song.trackID])
    }

    @Test("Liked toggle deletes liked playlist when last song is removed")
    func likedToggleDeletesEmptyPlaylist() throws {
        let (_, store) = try makeTempStore()
        let song = PlaylistEntry(trackID: "missing-liked", title: "Missing", artistName: "Artist", artworkURL: nil)

        #expect(store.toggleLiked(song) == .liked)
        #expect(store.likedSongsPlaylist() != nil)
        #expect(store.toggleLiked(song) == .unliked)
        #expect(store.likedSongsPlaylist() == nil)
        #expect(store.isLiked(trackID: song.trackID) == false)
    }

    @Test("Removing last song from liked playlist deletes the playlist")
    func removingLastLikedSongDeletesPlaylist() throws {
        let (_, store) = try makeTempStore()
        let song = PlaylistEntry(trackID: "liked-song", title: "Song", artistName: "Artist", artworkURL: nil)

        #expect(store.toggleLiked(song) == .liked)
        let playlist = store.likedSongsPlaylist()
        #expect(playlist?.songs.count == 1)

        if let playlist {
            store.removeSong(at: 0, from: playlist.id)
        }

        #expect(store.likedSongsPlaylist() == nil)
        #expect(store.isLiked(trackID: song.trackID) == false)
    }
}
