import Foundation
@testable import MuseAmp
import MuseAmpDatabaseKit
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

    @Test
    func `Reading lyrics that were never cached returns nil without a warning`() throws {
        let sandbox = TestLibrarySandbox()
        let database = try sandbox.makeDatabase()
        let recorder = LyricsStoreLogRecorder()
        let store = LyricsCacheStore(paths: database.paths, logSink: recorder.sink)

        #expect(store.lyrics(for: "track-without-lyrics") == nil)
        #expect(recorder.warningsAndErrors.isEmpty)
    }

    @Test
    func `Unreadable cached lyrics return nil and log a warning`() throws {
        let sandbox = TestLibrarySandbox()
        let database = try sandbox.makeDatabase()
        let recorder = LyricsStoreLogRecorder()
        let store = LyricsCacheStore(paths: database.paths, logSink: recorder.sink)
        let invalidUTF8 = Data([0xFF, 0xFE, 0xC0])
        try invalidUTF8.write(to: database.paths.lyricsCacheURL(for: "track-unreadable"))

        #expect(store.lyrics(for: "track-unreadable") == nil)
        #expect(recorder.warningsAndErrors.count == 1)
        #expect(recorder.warningsAndErrors.first?.contains("trackID=track-unreadable") == true)
    }
}

private final nonisolated class LyricsStoreLogRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [(level: DatabaseLogLevel, message: String)] = []

    var warningsAndErrors: [String] {
        lock.withLock {
            entries
                .filter { [.warning, .error, .critical].contains($0.level) }
                .map(\.message)
        }
    }

    var sink: LogSink {
        { [self] level, _, message in
            lock.withLock { entries.append((level, message)) }
        }
    }
}
