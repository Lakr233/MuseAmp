@testable import AmMusic
import AmMusicDatabaseKit
import Foundation
import Testing

@Suite(.serialized)
@MainActor
struct SongLibraryIndexerTests {
    @Test("syncLibrary removes unreadable audio files from disk and index")
    func syncLibraryPurgesUnreadableFiles() async throws {
        let sandbox = TestLibrarySandbox()
        let database = try sandbox.makeDatabase { _ in
            throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "unreadable"])
        }
        let paths = database.paths
        let indexer = SongLibraryIndexer(databaseManager: database.databaseManager)

        let relativePath = "album-1/broken-track.m4a"
        let fileURL = paths.absoluteAudioURL(for: relativePath)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not audio".utf8).write(to: fileURL)

        let artworkURL = paths.artworkCacheURL(for: "broken-track")
        try Data([0xFF, 0xD8, 0xFF]).write(to: artworkURL)

        let result = try await indexer.syncLibrary()

        #expect(result.filesScanned == 1)
        #expect(result.upserts == 0)
        #expect(result.deletions == 0)
        #expect(result.purged == 0)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
        #expect(!FileManager.default.fileExists(atPath: artworkURL.path))
        #expect(!FileManager.default.fileExists(atPath: fileURL.deletingLastPathComponent().path))
        #expect(try database.allTracks().isEmpty)
    }

    @Test("syncLibrary reports deletions for missing database rows")
    func syncLibraryDeletesMissingRows() async throws {
        let sandbox = TestLibrarySandbox()
        let database = try sandbox.makeDatabase()
        let paths = database.paths
        let indexer = SongLibraryIndexer(databaseManager: database.databaseManager)

        let inserted = try await sandbox.ingestTrack(
            makeMockTrack(
                trackID: "track-missing",
                relativePath: "album-2/track-missing.m4a"
            ),
            into: database
        )
        try FileManager.default.removeItem(
            at: paths.absoluteAudioURL(for: inserted.relativePath)
        )

        let result = try await indexer.syncLibrary()

        #expect(result.filesScanned == 0)
        #expect(result.upserts == 0)
        #expect(result.deletions == 1)
        #expect(result.purged == 0)
        #expect(try database.allTracks().isEmpty)
    }
}
