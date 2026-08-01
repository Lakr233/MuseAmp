import Foundation
@testable import MuseAmp
import MuseAmpDatabaseKit
import Testing

@Suite(.serialized)
@MainActor
struct SongLibraryIndexerTests {
    @Test
    func `syncLibrary removes unreadable audio files from disk and index`() async throws {
        let sandbox = TestLibrarySandbox()
        let database = try sandbox.makeDatabase { _ in
            // A deterministic validation failure is the only verdict that may
            // prune files; generic errors are treated as transient and keep
            // the file on disk.
            throw AudioFileValidationError.notPlayable(reason: "unreadable")
        }
        let paths = database.paths
        let indexer = SongLibraryIndexer(databaseManager: database.databaseManager)

        let relativePath = "album-1/broken-track.m4a"
        let fileURL = paths.absoluteAudioURL(for: relativePath)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        try Data("not audio".utf8).write(to: fileURL)

        let artworkURL = paths.artworkCacheURL(for: "broken-track")
        try Data([0xFF, 0xD8, 0xFF]).write(to: artworkURL)

        let result = try await indexer.syncLibrary()

        #expect(result.filesScanned == 1)
        #expect(result.upserts == 0)
        #expect(result.deletions == 0)
        #expect(result.removedInvalidFiles.count == 1)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
        #expect(!FileManager.default.fileExists(atPath: artworkURL.path))
        #expect(!FileManager.default.fileExists(atPath: fileURL.deletingLastPathComponent().path))
        #expect(try database.allTracks().isEmpty)
    }

    @Test
    func `syncLibrary reports deletions for missing database rows`() async throws {
        let sandbox = TestLibrarySandbox()
        let database = try sandbox.makeDatabase()
        let paths = database.paths
        let indexer = SongLibraryIndexer(databaseManager: database.databaseManager)

        let inserted = try await sandbox.ingestTrack(
            makeMockTrack(
                trackID: "track-missing",
                relativePath: "album-2/track-missing.m4a",
            ),
            into: database,
        )
        try FileManager.default.removeItem(
            at: paths.absoluteAudioURL(for: inserted.relativePath),
        )

        let result = try await indexer.syncLibrary()

        #expect(result.filesScanned == 0)
        #expect(result.upserts == 0)
        #expect(result.deletions == 1)
        #expect(result.removedInvalidFiles.isEmpty)
        #expect(try database.allTracks().isEmpty)
    }
}
