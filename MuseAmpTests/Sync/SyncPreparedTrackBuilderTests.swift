@preconcurrency import AVFoundation
import Foundation
@testable import MuseAmp
import MuseAmpDatabaseKit
import Testing

@Suite(.serialized)
struct SyncPreparedTrackBuilderTests {
    @Test
    func `prepare batch embeds metadata and builds manifest`() async throws {
        let sandbox = TestLibrarySandbox()
        let environment = sandbox.makeEnvironment()
        let builder = SyncPreparedTrackBuilder(
            paths: environment.paths,
            lyricsCacheStore: environment.lyricsCacheStore,
            apiClient: environment.apiClient,
        )

        let sourceURL = sandbox.baseDirectory.appendingPathComponent("source.m4a")
        try makeSilentM4A(at: sourceURL)
        try environment.lyricsCacheStore.saveLyrics("[00:01.00]Hello", for: "1234567890")

        let item = SongExportItem(
            sourceURL: sourceURL,
            artistName: "Artist",
            title: "Song",
            trackID: "1234567890",
            albumID: "9988776655",
            albumName: "Album",
            artworkURL: nil,
        )

        let batch = try await builder.prepareBatch(
            deviceName: "Device",
            items: [item],
        )
        defer { builder.cleanup(batch: batch) }

        #expect(batch.manifest.deviceName == "Device")
        #expect(batch.manifest.entries.count == 1)
        #expect(batch.manifest.entries.first?.trackID == "1234567890")
        #expect(batch.filesByTrackID["1234567890"] != nil)

        let preparedURL = try #require(batch.filesByTrackID["1234567890"])
        try await ExportMetadataProcessor.verifyEmbeddedMetadata(
            in: preparedURL,
            expectedTrackID: "1234567890",
        )
    }

    @Test
    func `prepare batch for transfer reads duration from audio file`() async throws {
        let sandbox = TestLibrarySandbox()
        let environment = sandbox.makeEnvironment()
        let builder = SyncPreparedTrackBuilder(
            paths: environment.paths,
        )

        let sourceURL = environment.paths.absoluteAudioURL(for: "source.m4a")
        try FileManager.default.createDirectory(
            at: sourceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        try makeSilentM4A(at: sourceURL)

        let track = AudioTrackRecord(
            trackID: "1234567890",
            albumID: "9988776655",
            fileExtension: "m4a",
            relativePath: "source.m4a",
            fileSizeBytes: 0,
            fileModifiedAt: Date(),
            durationSeconds: 42.5,
            title: "Song",
            artistName: "Artist",
            albumTitle: "Album",
        )

        let batch = try await builder.prepareBatch(
            deviceName: "Device",
            tracks: [track],
        )
        defer { builder.cleanup(batch: batch) }

        let entry = try #require(batch.manifest.entries.first)
        #expect(entry.trackID == "1234567890")
        // Duration is read from the actual audio file, not the track record.
        #expect(entry.durationSeconds > 0)
        #expect(batch.filesByTrackID["1234567890"] != nil)
    }

    @Test
    func `prepare batch records skipped items and filters session for unreadable sources`() async throws {
        let sandbox = TestLibrarySandbox()
        let environment = sandbox.makeEnvironment()
        let builder = SyncPreparedTrackBuilder(
            paths: environment.paths,
            lyricsCacheStore: environment.lyricsCacheStore,
            apiClient: environment.apiClient,
        )

        let goodURL = sandbox.baseDirectory.appendingPathComponent("good.m4a")
        try makeSilentM4A(at: goodURL)
        let missingURL = sandbox.baseDirectory.appendingPathComponent("missing.m4a")

        let goodItem = SongExportItem(
            sourceURL: goodURL,
            artistName: "Artist",
            title: "Good Song",
            trackID: "1111111111",
            albumID: "9988776655",
            albumName: "Album",
            artworkURL: nil,
        )
        let brokenItem = SongExportItem(
            sourceURL: missingURL,
            artistName: "Artist",
            title: "Broken Song",
            trackID: "2222222222",
            albumID: "9988776655",
            albumName: "Album",
            artworkURL: nil,
        )
        let session = SyncPlaylistSession(
            playlistName: "Playlist",
            orderedTrackIDs: ["1111111111", "2222222222"],
        )

        let batch = try await builder.prepareBatch(
            deviceName: "Device",
            items: [goodItem, brokenItem],
            session: session,
        )
        defer { builder.cleanup(batch: batch) }

        #expect(batch.manifest.entries.map(\.trackID) == ["1111111111"])
        #expect(batch.skippedItems.map(\.trackID) == ["2222222222"])
        #expect(batch.skippedItems.first?.title == "Broken Song")
        #expect(batch.skippedItems.first?.reason.isEmpty == false)

        let manifestSession = try #require(batch.manifest.session)
        #expect(manifestSession.playlistName == "Playlist")
        #expect(manifestSession.sessionID == session.sessionID)
        #expect(manifestSession.orderedTrackIDs == ["1111111111"])
        #expect(manifestSession.expectedTrackCount == 1)
        #expect(manifestSession.expectedUniqueTrackCount == 1)
    }

    @Test
    func `prepare batch keeps session untouched when nothing is skipped`() async throws {
        let sandbox = TestLibrarySandbox()
        let environment = sandbox.makeEnvironment()
        let builder = SyncPreparedTrackBuilder(
            paths: environment.paths,
            lyricsCacheStore: environment.lyricsCacheStore,
            apiClient: environment.apiClient,
        )

        let sourceURL = sandbox.baseDirectory.appendingPathComponent("source.m4a")
        try makeSilentM4A(at: sourceURL)

        let item = SongExportItem(
            sourceURL: sourceURL,
            artistName: "Artist",
            title: "Song",
            trackID: "1234567890",
            albumID: "9988776655",
            albumName: "Album",
            artworkURL: nil,
        )
        let session = SyncPlaylistSession(
            playlistName: "Playlist",
            orderedTrackIDs: ["1234567890"],
        )

        let batch = try await builder.prepareBatch(
            deviceName: "Device",
            items: [item],
            session: session,
        )
        defer { builder.cleanup(batch: batch) }

        #expect(batch.skippedItems.isEmpty)
        #expect(batch.manifest.session == session)
    }

    // MARK: - Metadata Presence Check

    @Test
    func `sourceHasCatalogComment returns true when metadata is present`() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = dir.appendingPathComponent("test.m4a")
        try makeSilentM4A(at: fileURL)

        let info = ExportMetadataProcessor.ExportInfo(
            trackID: "1234567890",
            albumID: "9988776655",
            artworkURL: nil,
            lyrics: nil,
            title: "Song",
            artistName: "Artist",
            albumName: "Album",
        )
        try await ExportMetadataProcessor.embedExportMetadata(info, into: fileURL)

        let builder = SyncPreparedTrackBuilder(
            paths: LibraryPaths(baseDirectory: dir),
        )
        let result = await builder.sourceHasCatalogComment(
            at: fileURL,
            expectedTrackID: "1234567890",
        )
        #expect(result == true)
    }

    @Test
    func `sourceHasCatalogComment returns false for bare file`() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = dir.appendingPathComponent("test.m4a")
        try makeSilentM4A(at: fileURL)

        let builder = SyncPreparedTrackBuilder(
            paths: LibraryPaths(baseDirectory: dir),
        )
        let result = await builder.sourceHasCatalogComment(
            at: fileURL,
            expectedTrackID: "1234567890",
        )
        #expect(result == false)
    }

    @Test
    func `sourceHasCatalogComment returns false when trackID mismatches`() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = dir.appendingPathComponent("test.m4a")
        try makeSilentM4A(at: fileURL)

        let info = ExportMetadataProcessor.ExportInfo(
            trackID: "1234567890",
            albumID: "9988776655",
            artworkURL: nil,
            lyrics: nil,
            title: "Song",
            artistName: "Artist",
            albumName: "Album",
        )
        try await ExportMetadataProcessor.embedExportMetadata(info, into: fileURL)

        let builder = SyncPreparedTrackBuilder(
            paths: LibraryPaths(baseDirectory: dir),
        )
        let result = await builder.sourceHasCatalogComment(
            at: fileURL,
            expectedTrackID: "9999999999",
        )
        #expect(result == false)
    }

    // MARK: - Export Skips Embedding

    @Test
    func `export skips embedding when metadata already present`() async throws {
        let sandbox = TestLibrarySandbox()
        let environment = sandbox.makeEnvironment()
        let builder = SyncPreparedTrackBuilder(
            paths: environment.paths,
            lyricsCacheStore: environment.lyricsCacheStore,
            apiClient: environment.apiClient,
        )

        let sourceURL = sandbox.baseDirectory.appendingPathComponent("source.m4a")
        try makeSilentM4A(at: sourceURL)

        let info = ExportMetadataProcessor.ExportInfo(
            trackID: "1234567890",
            albumID: "9988776655",
            artworkURL: nil,
            lyrics: nil,
            title: "Song",
            artistName: "Artist",
            albumName: "Album",
        )
        try await ExportMetadataProcessor.embedExportMetadata(info, into: sourceURL)

        let item = SongExportItem(
            sourceURL: sourceURL,
            artistName: "Artist",
            title: "Song",
            trackID: "1234567890",
            albumID: "9988776655",
            albumName: "Album",
            artworkURL: nil,
        )

        let batch = try await builder.prepareBatch(
            deviceName: "Device",
            items: [item],
        )
        defer { builder.cleanup(batch: batch) }

        let entry = try #require(batch.manifest.entries.first)
        #expect(entry.trackID == "1234567890")
    }

    // MARK: - includeLyrics Regression Tests

    @Test
    func `prepare batch with includeLyrics embeds metadata and lyrics`() async throws {
        let sandbox = TestLibrarySandbox()
        let environment = sandbox.makeEnvironment()
        let builder = SyncPreparedTrackBuilder(
            paths: environment.paths,
            lyricsCacheStore: environment.lyricsCacheStore,
            apiClient: environment.apiClient,
        )

        let sourceURL = sandbox.baseDirectory.appendingPathComponent("source.m4a")
        try makeSilentM4A(at: sourceURL)
        try environment.lyricsCacheStore.saveLyrics("[00:01.00]Line 1", for: "1234567890")

        let item = SongExportItem(
            sourceURL: sourceURL,
            artistName: "Artist",
            title: "Song",
            trackID: "1234567890",
            albumID: "9988776655",
            albumName: "Album",
            artworkURL: nil,
        )

        let batch = try await builder.prepareBatch(
            deviceName: "Device",
            items: [item],
            includeLyrics: true,
        )
        defer { builder.cleanup(batch: batch) }

        let preparedURL = try #require(batch.filesByTrackID["1234567890"])
        try await ExportMetadataProcessor.verifyEmbeddedMetadata(
            in: preparedURL,
            expectedTrackID: "1234567890",
        )
        let lyrics = try await lyricsFromMetadata(at: preparedURL)
        #expect(lyrics == "[00:01.00]Line 1")
    }

    @Test
    func `prepare batch with includeLyrics re-embeds over existing metadata`() async throws {
        let sandbox = TestLibrarySandbox()
        let environment = sandbox.makeEnvironment()
        let builder = SyncPreparedTrackBuilder(
            paths: environment.paths,
            lyricsCacheStore: environment.lyricsCacheStore,
            apiClient: environment.apiClient,
        )

        let sourceURL = sandbox.baseDirectory.appendingPathComponent("source.m4a")
        try makeSilentM4A(at: sourceURL)

        // Pre-embed metadata without lyrics.
        let info = ExportMetadataProcessor.ExportInfo(
            trackID: "1234567890",
            albumID: "9988776655",
            artworkURL: nil,
            lyrics: nil,
            title: "Song",
            artistName: "Artist",
            albumName: "Album",
        )
        try await ExportMetadataProcessor.embedExportMetadata(info, into: sourceURL)

        try environment.lyricsCacheStore.saveLyrics("[00:02.00]Line 2", for: "1234567890")

        let item = SongExportItem(
            sourceURL: sourceURL,
            artistName: "Artist",
            title: "Song",
            trackID: "1234567890",
            albumID: "9988776655",
            albumName: "Album",
            artworkURL: nil,
        )

        let batch = try await builder.prepareBatch(
            deviceName: "Device",
            items: [item],
            includeLyrics: true,
        )
        defer { builder.cleanup(batch: batch) }

        let preparedURL = try #require(batch.filesByTrackID["1234567890"])
        let lyrics = try await lyricsFromMetadata(at: preparedURL)
        #expect(lyrics == "[00:02.00]Line 2")
    }

    @Test
    func `fetchOrCachedLyrics falls back to apiClient when cache miss`() async throws {
        let sandbox = TestLibrarySandbox()
        let environment = sandbox.makeEnvironment()

        // Ensure cache is empty.
        try? environment.lyricsCacheStore.removeLyrics(for: "1234567890")

        // Set up a mock URLProtocol to return lyrics JSON.
        let mockJSON = Data(
            #"""
            {
              "subsonic-response": {
                "status": "ok",
                "version": "1.16.1",
                "lyrics": {
                  "value": "[00:03.00]Fetched Line"
                }
              }
            }
            """#.utf8,
        )
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"],
            )!
            return (mockJSON, response)
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let mockSession = URLSession(configuration: config)
        let mockAPIClient = try APIClient(baseURL: #require(URL(string: "https://test.example.com")), session: mockSession)

        let builder = SyncPreparedTrackBuilder(
            paths: environment.paths,
            lyricsCacheStore: environment.lyricsCacheStore,
            apiClient: mockAPIClient,
        )

        let lyrics = await builder.fetchOrCachedLyrics(for: "1234567890")
        #expect(lyrics == "[00:03.00]Fetched Line")

        // Verify it was cached.
        let cached = environment.lyricsCacheStore.lyrics(for: "1234567890")
        #expect(cached == "[00:03.00]Fetched Line")
    }
}

private extension SyncPreparedTrackBuilderTests {
    func makeSilentM4A(at url: URL) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64000,
        ]
        let sourceFormat = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let frameCount: AVAudioFrameCount = 88200
        let pcmBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: frameCount)!
        pcmBuffer.frameLength = frameCount

        let audioFile = try AVAudioFile(
            forWriting: url,
            settings: settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false,
        )
        try audioFile.write(from: pcmBuffer)
    }

    func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SyncBuilderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func lyricsFromMetadata(at fileURL: URL) async throws -> String? {
        let asset = AVURLAsset(url: fileURL)
        let items = try await AVMetadataHelper.collectMetadataItems(from: asset)
        for item in items where item.identifier == .iTunesMetadataLyrics {
            return try? await item.load(.stringValue)
        }
        return nil
    }
}

final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (Data, URLResponse))?

    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            fatalError("MockURLProtocol.handler not set")
        }
        let (data, response) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
