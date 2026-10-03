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
        #expect(batch.skippedItems.first?.isSourceUnreadable == true)

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

    // MARK: - Lyrics Cached After Download

    @Test
    func `send embeds lyrics that were cached after the download`() async throws {
        let sandbox = TestLibrarySandbox()
        let environment = sandbox.makeEnvironment()
        let builder = SyncPreparedTrackBuilder(
            paths: environment.paths,
            lyricsCacheStore: environment.lyricsCacheStore,
            apiClient: environment.apiClient,
        )

        let sourceURL = sandbox.baseDirectory.appendingPathComponent("source.m4a")
        try makeSilentM4A(at: sourceURL)
        try await ExportMetadataProcessor.embedExportMetadata(
            makeExportInfo(lyrics: nil),
            into: sourceURL,
        )
        try environment.lyricsCacheStore.saveLyrics("[00:05.00]Fetched later", for: "1234567890")

        let batch = try await builder.prepareBatch(
            deviceName: "Device",
            items: [makeItem(sourceURL: sourceURL)],
        )
        defer { builder.cleanup(batch: batch) }

        let preparedURL = try #require(batch.filesByTrackID["1234567890"])
        #expect(try await lyricsFromMetadata(at: preparedURL) == "[00:05.00]Fetched later")
        try await ExportMetadataProcessor.verifyEmbeddedMetadata(in: preparedURL, expectedTrackID: "1234567890")
        // The library copy itself is left alone.
        #expect(try await lyricsFromMetadata(at: sourceURL) == nil)
    }

    @Test
    func `send replaces embedded lyrics with the edited cached copy`() async throws {
        let sandbox = TestLibrarySandbox()
        let environment = sandbox.makeEnvironment()
        let builder = SyncPreparedTrackBuilder(
            paths: environment.paths,
            lyricsCacheStore: environment.lyricsCacheStore,
            apiClient: environment.apiClient,
        )

        let sourceURL = sandbox.baseDirectory.appendingPathComponent("source.m4a")
        try makeSilentM4A(at: sourceURL)
        try await ExportMetadataProcessor.embedExportMetadata(
            makeExportInfo(lyrics: "[00:01.00]Old line"),
            into: sourceURL,
        )
        try environment.lyricsCacheStore.saveLyrics("[00:01.00]Edited line", for: "1234567890")

        let batch = try await builder.prepareBatch(
            deviceName: "Device",
            items: [makeItem(sourceURL: sourceURL)],
        )
        defer { builder.cleanup(batch: batch) }

        let preparedURL = try #require(batch.filesByTrackID["1234567890"])
        #expect(try await lyricsFromMetadata(at: preparedURL) == "[00:01.00]Edited line")
    }

    @Test
    func `lyrics update keeps the artwork URL from the downloaded comment`() async throws {
        let sandbox = TestLibrarySandbox()
        let environment = sandbox.makeEnvironment()
        let builder = SyncPreparedTrackBuilder(
            paths: environment.paths,
            lyricsCacheStore: environment.lyricsCacheStore,
            apiClient: environment.apiClient,
        )

        let sourceURL = sandbox.baseDirectory.appendingPathComponent("source.m4a")
        try makeSilentM4A(at: sourceURL)
        let artworkURL = try #require(URL(string: "https://artwork.example.com/1234567890/600x600.jpg"))
        var downloadInfo = makeExportInfo(lyrics: "[00:01.00]Old line")
        downloadInfo.artworkURL = artworkURL
        try await ExportMetadataProcessor.embedExportMetadata(downloadInfo, into: sourceURL)
        try environment.lyricsCacheStore.saveLyrics("[00:01.00]Edited line", for: "1234567890")

        let batch = try await builder.prepareBatch(
            deviceName: "Device",
            items: [makeItem(sourceURL: sourceURL)],
        )
        defer { builder.cleanup(batch: batch) }

        let preparedURL = try #require(batch.filesByTrackID["1234567890"])
        #expect(try await lyricsFromMetadata(at: preparedURL) == "[00:01.00]Edited line")
        let comment = try #require(try await commentFromMetadata(at: preparedURL))
        #expect(TrackArtworkRepairService.embeddedArtworkURL(fromComment: comment) == artworkURL)
        try await ExportMetadataProcessor.verifyEmbeddedMetadata(in: preparedURL, expectedTrackID: "1234567890")
    }

    @Test
    func `send keeps embedded lyrics when the cache has none`() async throws {
        let sandbox = TestLibrarySandbox()
        let environment = sandbox.makeEnvironment()
        let builder = SyncPreparedTrackBuilder(
            paths: environment.paths,
            lyricsCacheStore: environment.lyricsCacheStore,
            apiClient: environment.apiClient,
        )

        let sourceURL = sandbox.baseDirectory.appendingPathComponent("source.m4a")
        try makeSilentM4A(at: sourceURL)
        try await ExportMetadataProcessor.embedExportMetadata(
            makeExportInfo(lyrics: "[00:01.00]Embedded line"),
            into: sourceURL,
        )

        let batch = try await builder.prepareBatch(
            deviceName: "Device",
            items: [makeItem(sourceURL: sourceURL)],
        )
        defer { builder.cleanup(batch: batch) }

        let preparedURL = try #require(batch.filesByTrackID["1234567890"])
        #expect(try await lyricsFromMetadata(at: preparedURL) == "[00:01.00]Embedded line")
    }

    // MARK: - Healthy Songs Are Not Reported Unreadable

    @Test
    func `long artist and title still prepare`() async throws {
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
            artistName: String(repeating: "Philharmonic Orchestra ", count: 8),
            title: String(repeating: "交响曲第九号 ", count: 12),
            trackID: "1234567890",
            albumID: "9988776655",
            albumName: "Album",
            artworkURL: nil,
        )
        #expect(item.preferredFileBaseName.utf8.count > 255)

        let batch = try await builder.prepareBatch(deviceName: "Device", items: [item])
        defer { builder.cleanup(batch: batch) }

        #expect(batch.skippedItems.isEmpty)
        let preparedURL = try #require(batch.filesByTrackID["1234567890"])
        #expect(preparedURL.lastPathComponent.utf8.count <= 255)
    }

    @Test
    func `lyrics export writes a file for a long artist and title`() async throws {
        let sandbox = TestLibrarySandbox()
        let environment = sandbox.makeEnvironment()
        try environment.lyricsCacheStore.saveLyrics("[00:01.00]Line", for: "1234567890")
        let item = SongExportItem(
            sourceURL: sandbox.baseDirectory.appendingPathComponent("source.m4a"),
            artistName: String(repeating: "Philharmonic Orchestra ", count: 8),
            title: String(repeating: "交响曲第九号 ", count: 12),
            trackID: "1234567890",
            albumID: "9988776655",
            albumName: "Album",
            artworkURL: nil,
        )
        #expect(item.preferredFileBaseName.utf8.count > 255)

        let presenter = SongExportPresenter(
            viewController: nil,
            lyricsStore: environment.lyricsCacheStore,
        )
        let result = try await presenter.prepareLyricsFiles(items: [item], progress: nil)
        defer { try? FileManager.default.removeItem(at: result.cleanupDirectory) }

        let lyricsURL = try #require(result.urls.first)
        #expect(lyricsURL.lastPathComponent.utf8.count <= 255)
        #expect(try String(contentsOf: lyricsURL, encoding: .utf8) == "[00:01.00]Line")
    }

    @Test
    func `truncated file names stay within the byte limit on a character boundary`() {
        let name = String(repeating: "交响曲", count: 100)
        let truncated = SyncPreparedTrackBuilder.truncatedFileBaseName(name, fallback: "1234567890")

        #expect(truncated.utf8.count <= SyncPreparedTrackBuilder.maxFileBaseNameByteCount)
        #expect(!truncated.isEmpty)
        #expect(name.hasPrefix(truncated))
        #expect(SyncPreparedTrackBuilder.truncatedFileBaseName("Short", fallback: "1") == "Short")
    }

    @Test
    func `a readable song skipped for another reason is not reported unreadable`() async throws {
        let sandbox = TestLibrarySandbox()
        let environment = sandbox.makeEnvironment()
        let builder = SyncPreparedTrackBuilder(
            paths: environment.paths,
            lyricsCacheStore: environment.lyricsCacheStore,
            apiClient: environment.apiClient,
        )

        let goodURL = sandbox.baseDirectory.appendingPathComponent("good.m4a")
        try makeSilentM4A(at: goodURL)
        // Playable, but it carries no catalog comment and has no album ID to
        // embed, so preparing it fails for a reason unrelated to the file.
        let playableURL = sandbox.baseDirectory.appendingPathComponent("playable.m4a")
        try makeSilentM4A(at: playableURL)

        let batch = try await builder.prepareBatch(
            deviceName: "Device",
            items: [
                makeItem(sourceURL: goodURL),
                SongExportItem(
                    sourceURL: playableURL,
                    artistName: "Artist",
                    title: "No Album",
                    trackID: "2222222222",
                    albumID: nil,
                    albumName: nil,
                    artworkURL: nil,
                ),
            ],
        )
        defer { builder.cleanup(batch: batch) }

        let skipped = try #require(batch.skippedItems.first)
        #expect(skipped.trackID == "2222222222")
        #expect(skipped.isSourceUnreadable == false)
        #expect(batch.skippedItems.areAllSourcesUnreadable == false)
    }

    // MARK: - Cancellation

    @Test
    func `cancelling preparation returns no batch and removes its scratch copies`() async throws {
        let sandbox = TestLibrarySandbox()
        let environment = sandbox.makeEnvironment()
        let builder = SyncPreparedTrackBuilder(
            paths: environment.paths,
            lyricsCacheStore: environment.lyricsCacheStore,
        )

        let sourceURL = sandbox.baseDirectory.appendingPathComponent("source.m4a")
        try makeSilentM4A(at: sourceURL)
        let uniqueTitle = "Cancelled \(UUID().uuidString)"
        let item = SongExportItem(
            sourceURL: sourceURL,
            artistName: "Artist",
            title: uniqueTitle,
            trackID: "1234567890",
            albumID: "9988776655",
            albumName: "Album",
            artworkURL: nil,
        )

        // Cancel while the only song is being prepared: the cancel lands
        // after the loop's own cancellation check.
        let holder = PreparationTaskHolder()
        let task = Task {
            try await builder.prepareBatch(
                deviceName: "Device",
                items: [item],
                progress: { _, _ in holder.cancel() },
            )
        }
        holder.task = task

        do {
            let batch = try await task.value
            builder.cleanup(batch: batch)
            Issue.record("Expected a cancelled preparation to hand back no batch")
        } catch is CancellationError {
            // Expected.
        }

        let preparedName = "Artist - \(uniqueTitle).m4a"
        let scratchDirectories = try FileManager.default
            .contentsOfDirectory(at: FileManager.default.temporaryDirectory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix(SyncTransferSession.temporaryDirectoryPrefix) }
        let leftovers = scratchDirectories.filter {
            FileManager.default.fileExists(atPath: $0.appendingPathComponent(preparedName).path)
        }
        #expect(leftovers.isEmpty)
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

    func makeExportInfo(lyrics: String?) -> ExportMetadataProcessor.ExportInfo {
        ExportMetadataProcessor.ExportInfo(
            trackID: "1234567890",
            albumID: "9988776655",
            artworkURL: nil,
            lyrics: lyrics,
            title: "Song",
            artistName: "Artist",
            albumName: "Album",
        )
    }

    func makeItem(sourceURL: URL) -> SongExportItem {
        SongExportItem(
            sourceURL: sourceURL,
            artistName: "Artist",
            title: "Song",
            trackID: "1234567890",
            albumID: "9988776655",
            albumName: "Album",
            artworkURL: nil,
        )
    }

    func commentFromMetadata(at fileURL: URL) async throws -> String? {
        let asset = AVURLAsset(url: fileURL)
        let items = try await AVMetadataHelper.collectMetadataItems(from: asset)
        for item in items where item.identifier == .iTunesMetadataUserComment {
            return try await item.load(.stringValue)
        }
        return nil
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

private final class PreparationTaskHolder {
    var task: Task<PreparedTransferBatch, any Error>?

    func cancel() {
        task?.cancel()
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
