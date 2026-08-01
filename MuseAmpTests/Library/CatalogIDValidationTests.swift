import Foundation
@testable import MuseAmp
import MuseAmpDatabaseKit
import Testing

// MARK: - isCatalogID Tests

@Suite(.serialized)
struct CatalogIDTests {
    @Test
    func `numeric string is a catalog ID`() {
        #expect("1234567890".isCatalogID)
    }

    @Test
    func `single digit is a catalog ID`() {
        #expect("0".isCatalogID)
    }

    @Test
    func `empty string is not a catalog ID`() {
        #expect(!"".isCatalogID)
    }

    @Test
    func `UUID string is not a catalog ID`() {
        #expect(!"D07CF011-0737-4F02-8E5B-859BB6DDF179".isCatalogID)
    }

    @Test
    func `alphabetic string is not a catalog ID`() {
        #expect(!"unknown".isCatalogID)
    }

    @Test
    func `artist-album folder name is not a catalog ID`() {
        #expect(!"王靖雯 - 大概是因为你的到来".isCatalogID)
    }

    @Test
    func `mixed alphanumeric is not a catalog ID`() {
        #expect(!"abc123".isCatalogID)
    }
}

// MARK: - Managed Path Tests

@Suite(.serialized)
@MainActor
struct PathConformanceTests {
    @Test
    func `syncLibrary removes files outside the managed album/track layout`() async throws {
        let sandbox = TestLibrarySandbox()
        let locations = LibraryPaths(baseDirectory: sandbox.baseDirectory)
        try locations.ensureDirectoriesExist()
        let database = try sandbox.makeDatabase()
        let indexer = SongLibraryIndexer(databaseManager: database.databaseManager)

        let relativePath = "Artist/Album/Track.m4a"
        let fileURL = locations.absoluteAudioURL(for: relativePath)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        try Data("not audio".utf8).write(to: fileURL)

        let result = try await indexer.syncLibrary()

        #expect(result.filesScanned == 1)
        #expect(result.upserts == 0)
        #expect(result.deletions == 0)
        #expect(result.removedInvalidFiles.count == 1)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test
    func `syncLibrary prunes unreadable opaque files`() async throws {
        let sandbox = TestLibrarySandbox()
        let database = try sandbox.makeDatabase { _ in
            throw AudioFileValidationError.notPlayable(reason: "unreadable")
        }
        let paths = database.paths
        let indexer = SongLibraryIndexer(databaseManager: database.databaseManager)

        let relativePath = "album-opaque/track-opaque.m4a"
        let fileURL = paths.absoluteAudioURL(for: relativePath)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        try Data("not audio".utf8).write(to: fileURL)

        let result = try await indexer.syncLibrary()

        #expect(result.filesScanned == 1)
        #expect(result.upserts == 0)
        #expect(result.deletions == 0)
        #expect(result.removedInvalidFiles.count == 1)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
    }
}
