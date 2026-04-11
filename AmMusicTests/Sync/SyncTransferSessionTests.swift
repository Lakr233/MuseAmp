@testable import AmMusic
import AmMusicDatabaseKit
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
                    durationSeconds: 100,
                    fileSizeBytes: 1,
                    fileExtension: "m4a",
                ),
                SyncManifestEntry(
                    trackID: "2222222222",
                    albumID: "9988776656",
                    title: "Missing",
                    artistName: "Artist",
                    albumTitle: "Album",
                    durationSeconds: 100,
                    fileSizeBytes: 1,
                    fileExtension: "m4a",
                ),
            ],
        )

        let missing = await session.missingEntries(in: manifest)
        #expect(missing.map(\.trackID) == ["2222222222"])
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
}
