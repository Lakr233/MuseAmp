import Foundation
@testable import MuseAmp
import MuseAmpDatabaseKit
import Testing

@Suite(.serialized)
struct SyncTransferSessionTests {
    @Test
    func `missing entries only include tracks not already in library`() async throws {
        let sandbox = TestLibrarySandbox()
        let environment = sandbox.makeEnvironment()
        let session = environment.makeSyncTransferSession()

        let existingTrack = makeMockTrack(trackID: "1111111111")
        _ = try await sandbox.ingestTrack(existingTrack, into: environment.libraryDatabase)

        let manifest = SyncManifest(
            deviceName: "Device",
            entries: [
                SyncManifestEntry(
                    trackID: "1111111111",
                    albumID: "9988776655",
                    title: "Existing",
                    artistName: "Artist",
                    albumTitle: "Album",
                    durationSeconds: 213,
                    fileExtension: "m4a",
                ),
                SyncManifestEntry(
                    trackID: "2222222222",
                    albumID: "9988776656",
                    title: "Missing",
                    artistName: "Artist",
                    albumTitle: "Album",
                    durationSeconds: 100,
                    fileExtension: "m4a",
                ),
            ],
        )

        let missing = await session.missingEntries(in: manifest)
        #expect(missing.map(\.trackID) == ["2222222222"])
    }

    @Test
    func `missing entries include tracks with mismatched duration`() async throws {
        let sandbox = TestLibrarySandbox()
        let environment = sandbox.makeEnvironment()
        let session = environment.makeSyncTransferSession()

        let existingTrack = makeMockTrack(trackID: "1111111111")
        _ = try await sandbox.ingestTrack(existingTrack, into: environment.libraryDatabase)

        let manifest = SyncManifest(
            deviceName: "Device",
            entries: [
                SyncManifestEntry(
                    trackID: "1111111111",
                    albumID: "9988776655",
                    title: "Existing But Different Duration",
                    artistName: "Artist",
                    albumTitle: "Album",
                    durationSeconds: 200,
                    fileExtension: "m4a",
                ),
            ],
        )

        let eligible = await session.missingEntries(in: manifest)
        #expect(eligible.map(\.trackID) == ["1111111111"])
    }

    @Test
    func `missing entries skip tracks with matching duration within tolerance`() async throws {
        let sandbox = TestLibrarySandbox()
        let environment = sandbox.makeEnvironment()
        let session = environment.makeSyncTransferSession()

        let existingTrack = makeMockTrack(trackID: "1111111111")
        _ = try await sandbox.ingestTrack(existingTrack, into: environment.libraryDatabase)

        // The mock track has durationSeconds = 213.
        // An entry with duration within 1s tolerance should not be flagged.
        let manifest = SyncManifest(
            deviceName: "Device",
            entries: [
                SyncManifestEntry(
                    trackID: "1111111111",
                    albumID: "9988776655",
                    title: "Same Duration",
                    artistName: "Artist",
                    albumTitle: "Album",
                    durationSeconds: 213.8,
                    fileExtension: "m4a",
                ),
            ],
        )

        let missing = await session.missingEntries(in: manifest)
        #expect(missing.isEmpty)
    }

    @Test
    func `resolve endpoints falls back to qr endpoints when bonjour is unavailable`() async {
        let sandbox = TestLibrarySandbox()
        let environment = sandbox.makeEnvironment()
        let session = environment.makeSyncTransferSession()

        let fallback = SyncEndpoint(host: "speaker-room.local", port: 52301)
        let connectionInfo = SyncConnectionInfo(
            serviceName: "Device",
            password: "482916",
            deviceName: "Device",
            fallbackEndpoints: [fallback],
        )

        let endpoints = await session.resolveEndpoints(for: connectionInfo)
        #expect(endpoints == [fallback])
    }

    @Test
    func `receive summary counts songs already in the library as skipped`() {
        let summary = SyncReceiveSummary(
            offeredCount: 8,
            requestedCount: 5,
            downloadedCount: 5,
            importResult: AudioImportResult(succeeded: 5, duplicates: 0, noMetadata: 0, errors: 0),
        )

        #expect(summary.imported == 5)
        #expect(summary.skipped == 3)
        #expect(summary.failed == 0)
    }

    @Test
    func `receive summary accounts for every offered song after failures`() {
        let summary = SyncReceiveSummary(
            offeredCount: 8,
            requestedCount: 6,
            downloadedCount: 4,
            importResult: AudioImportResult(succeeded: 2, duplicates: 1, noMetadata: 0, errors: 1),
        )

        #expect(summary.imported == 2)
        #expect(summary.skipped == 3)
        #expect(summary.failed == 3)
        #expect(summary.imported + summary.skipped + summary.failed == 8)
    }

    @Test
    func `importing a download that vanished counts it as failed`() async {
        let sandbox = TestLibrarySandbox()
        let environment = sandbox.makeEnvironment()
        let session = environment.makeSyncTransferSession()
        let vanishedURL = sandbox.baseDirectory
            .appendingPathComponent("am-transfer-receive-gone", isDirectory: true)
            .appendingPathComponent("9100000203.m4a")

        let result = await session.importDownloadedFiles([vanishedURL])

        #expect(result.succeeded == 0)
        #expect(result.errors == 1)
    }

    @Test
    func `stale transfer directories are swept and other entries are kept`() throws {
        let sandbox = TestLibrarySandbox()
        let root = sandbox.baseDirectory.appendingPathComponent("tmp", isDirectory: true)
        let senderDirectory = root.appendingPathComponent("am-transfer-8EFB9D8F", isDirectory: true)
        let receiverDirectory = root.appendingPathComponent("am-transfer-receive-15C48AED", isDirectory: true)
        let unrelatedDirectory = root.appendingPathComponent("ExportMetadataTests-1", isDirectory: true)
        for directory in [senderDirectory, receiverDirectory, unrelatedDirectory] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("partial".utf8).write(to: directory.appendingPathComponent("9100000101.m4a"))
        }

        let removedCount = SyncTransferSession.removeStaleTemporaryDirectories(in: root, minimumAge: 0)

        #expect(removedCount == 2)
        #expect(!FileManager.default.fileExists(atPath: senderDirectory.path))
        #expect(!FileManager.default.fileExists(atPath: receiverDirectory.path))
        #expect(FileManager.default.fileExists(atPath: unrelatedDirectory.path))
    }

    @Test
    func `age gated sweep keeps transfer directories that are still in use`() throws {
        let sandbox = TestLibrarySandbox()
        let root = sandbox.baseDirectory.appendingPathComponent("tmp", isDirectory: true)
        let directory = root.appendingPathComponent("am-transfer-D9D182D9", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        #expect(SyncTransferSession.removeStaleTemporaryDirectories(in: root, minimumAge: 3600) == 0)
        #expect(FileManager.default.fileExists(atPath: directory.path))

        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -7200)],
            ofItemAtPath: directory.path,
        )
        #expect(SyncTransferSession.removeStaleTemporaryDirectories(in: root, minimumAge: 3600) == 1)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }
}
