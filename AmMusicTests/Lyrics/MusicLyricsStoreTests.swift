@testable import AmMusic
import AmMusicDatabaseKit
import Foundation
import Testing

@Suite(.serialized)
struct MusicLyricsStoreTests {
    @Test
    func `Offline lyrics store saves, loads, and removes lyrics`() throws {
        let sandbox = TestLibrarySandbox()
        let database = try sandbox.makeDatabase()
        let paths = database.paths
        let store = LyricsCacheStore(paths: paths)

        try store.saveLyrics("[00:01.00]Hello", for: "track-1")

        #expect(store.lyrics(for: "track-1") == "[00:01.00]Hello")

        try store.removeLyrics(for: "track-1")

        #expect(store.lyrics(for: "track-1") == nil)
    }

    @Test
    func `Offline lyrics store preserves empty lyrics markers`() throws {
        let sandbox = TestLibrarySandbox()
        let database = try sandbox.makeDatabase()
        let paths = database.paths
        let store = LyricsCacheStore(paths: paths)

        try store.saveLyrics("", for: "track-empty")

        #expect(store.lyrics(for: "track-empty") == "")
    }

    @Test
    func `Removing all offline songs also clears cached lyrics`() async throws {
        let sandbox = TestLibrarySandbox()
        let database = try sandbox.makeDatabase()
        let paths = database.paths
        let store = LyricsCacheStore(paths: paths)

        _ = try await sandbox.ingestTrack(makeMockTrack(), into: database)
        try store.saveLyrics("[00:01.00]Hello", for: "track-1")

        try await database.removeAllStoredSongs()

        #expect(store.lyrics(for: "track-1") == nil)
        #expect(FileManager.default.fileExists(atPath: paths.lyricsCacheDirectory.path))
    }
}
