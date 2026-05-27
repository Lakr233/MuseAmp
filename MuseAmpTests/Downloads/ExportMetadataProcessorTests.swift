@preconcurrency import AVFoundation
import Dispatch
import Foundation
@testable import MuseAmp
import MuseAmpDatabaseKit
import TagLibAudioMetadata
import Testing

@Suite(.serialized)
struct ExportMetadataProcessorTests {
    private func makeSilentM4A(at url: URL) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64000,
        ]
        let sourceFormat = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let frameCount: AVAudioFrameCount = 44100
        let pcmBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: frameCount)!
        pcmBuffer.frameLength = frameCount

        let audioFile = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        try audioFile.write(from: pcmBuffer)
    }

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExportMetadataTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func readMetadata(from url: URL) async throws -> [AVMetadataItem] {
        let asset = AVURLAsset(url: url)
        return try await asset.load(.metadata)
    }

    private func stringValue(of item: AVMetadataItem) async -> String? {
        try? await item.load(.stringValue)
    }

    private func isComment(_ item: AVMetadataItem) -> Bool {
        item.identifier == .iTunesMetadataUserComment
            || AVMetadataHelper.matches(item, tokens: ["comment"])
    }

    private func isLyrics(_ item: AVMetadataItem) -> Bool {
        item.identifier == .iTunesMetadataLyrics
            || AVMetadataHelper.matches(item, tokens: ["lyrics"])
    }

    private func makeImporter(
        sandbox: TestLibrarySandbox,
    ) throws -> AudioFileImporter {
        let database = try sandbox.makeDatabase()
        return try makeImporter(database: database)
    }

    private func makeImportDatabase(
        sandbox: TestLibrarySandbox,
    ) throws -> MusicLibraryDatabase {
        let metadataReader = EmbeddedMetadataReader()
        return try sandbox.makeDatabase { url in
            let trackID = url.deletingPathExtension().lastPathComponent
            let albumID = url.deletingLastPathComponent().lastPathComponent.nilIfEmpty ?? "unknown"
            return AudioFileInspection(
                metadata: ImportedTrackMetadata(
                    trackID: trackID,
                    albumID: albumID,
                    title: trackID,
                    artistName: "Artist",
                    albumTitle: albumID,
                    sourceKind: .unknown,
                ),
                embeddedArtwork: await metadataReader.extractArtwork(from: url),
            )
        }
    }

    private func makeImporter(
        database: MusicLibraryDatabase,
    ) throws -> AudioFileImporter {
        let metadataReader = EmbeddedMetadataReader()
        let indexer = SongLibraryIndexer(databaseManager: database.databaseManager)
        let apiClient = try APIClient(baseURL: #require(URL(string: "https://example.com")))
        return AudioFileImporter(
            paths: database.paths,
            database: database,
            metadataReader: metadataReader,
            libraryIndexer: indexer,
            apiClient: apiClient,
        )
    }

    private func tinyArtworkData() -> Data {
        let base64 = [
            "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAP//////////////////////////////",
            "////////////////////////////////////////////////////////2wBDAf//////",
            "////////////////////////////////////////////////////////////////wAARC",
            "AABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAX/xAAUEAEAAAAAAA",
            "AAAAAAAAAAAAAA/9oADAMBAAIQAxAAAAF//8QAFBABAAAAAAAAAAAAAAAAAAAAAP/a",
            "AAgBAQABBQJ//8QAFBEBAAAAAAAAAAAAAAAAAAAAAP/aAAgBAwEBPwF//8QAFBEBAA",
            "AAAAAAAAAAAAAAAAAAAP/aAAgBAgEBPwF//8QAFBABAAAAAAAAAAAAAAAAAAAAAP/a",
            "AAgBAQAGPwJ//8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABPyF//9k=",
        ].joined()
        return Data(base64Encoded: base64)!
    }

    private func embedPlainMetadata(
        into fileURL: URL,
        title: String? = nil,
        artistName: String? = nil,
        albumName: String? = nil,
        artworkData: Data? = nil,
    ) async throws {
        let asset = AVURLAsset(url: fileURL)
        guard await (try? asset.load(.isReadable)) == true else {
            throw NSError(domain: "ExportMetadataProcessorTests", code: 1)
        }
        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetPassthrough,
        ) else {
            throw NSError(domain: "ExportMetadataProcessorTests", code: 2)
        }

        var metadata: [AVMetadataItem] = []
        if let title {
            metadata.append(metadataItem(identifier: .commonIdentifierTitle, value: title))
            metadata.append(metadataItem(identifier: .iTunesMetadataSongName, value: title))
        }
        if let artistName {
            metadata.append(metadataItem(identifier: .commonIdentifierArtist, value: artistName))
            metadata.append(metadataItem(identifier: .iTunesMetadataArtist, value: artistName))
        }
        if let albumName {
            metadata.append(metadataItem(identifier: .commonIdentifierAlbumName, value: albumName))
            metadata.append(metadataItem(identifier: .iTunesMetadataAlbum, value: albumName))
        }
        if let artworkData {
            metadata.append(contentsOf: DownloadArtworkProcessor.artworkMetadataItems(data: artworkData))
        }

        let tempURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
            .appendingPathExtension("m4a")
        exportSession.outputURL = tempURL
        exportSession.outputFileType = .m4a
        exportSession.shouldOptimizeForNetworkUse = false
        exportSession.metadata = metadata

        do {
            try await DownloadArtworkProcessor.export(exportSession, timeout: 30)
            _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: tempURL)
            var tagMetadata = BasicMetadata.empty
            tagMetadata.title = title ?? ""
            tagMetadata.artist = artistName ?? ""
            tagMetadata.album = albumName ?? ""
            tagMetadata.artworkData = artworkData
            try TagLibMetadataManager.writeMetadataWithVerification(tagMetadata, to: fileURL)
        } catch {
            if FileManager.default.fileExists(atPath: tempURL.path) {
                try? FileManager.default.removeItem(at: tempURL)
            }
            throw error
        }
    }

    private func metadataItem(identifier: AVMetadataIdentifier, value: String) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = identifier
        item.value = value as NSString
        return item.copy() as! AVMetadataItem
    }

    // MARK: - Tests

    @Test
    func `embeds title, artist, and album metadata`() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = dir.appendingPathComponent("test.m4a")
        try makeSilentM4A(at: fileURL)

        let info = ExportMetadataProcessor.ExportInfo(
            trackID: "track-42",
            albumID: "album-7",
            artworkURL: URL(string: "https://example.com/art.jpg"),
            lyrics: "Hello world lyrics",
            title: "One",
            artistName: "Ed Sheeran",
            albumName: "Multiply",
        )
        try await ExportMetadataProcessor.embedExportMetadata(info, into: fileURL)

        let metadata = try await readMetadata(from: fileURL)

        let titles = metadata.filter {
            $0.identifier == .commonIdentifierTitle || $0.identifier == .iTunesMetadataSongName
        }
        #expect(!titles.isEmpty, "Expected title metadata")
        for item in titles {
            let value = await stringValue(of: item)
            #expect(value == "One")
        }

        let artists = metadata.filter {
            $0.identifier == .commonIdentifierArtist || $0.identifier == .iTunesMetadataArtist
        }
        #expect(!artists.isEmpty, "Expected artist metadata")
        for item in artists {
            let value = await stringValue(of: item)
            #expect(value == "Ed Sheeran")
        }

        let albums = metadata.filter {
            $0.identifier == .commonIdentifierAlbumName || $0.identifier == .iTunesMetadataAlbum
        }
        #expect(!albums.isEmpty, "Expected album metadata")
        for item in albums {
            let value = await stringValue(of: item)
            #expect(value == "Multiply")
        }
    }

    @Test
    func `embeds JSON comment with trackID, albumID, artworkURL`() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = dir.appendingPathComponent("test.m4a")
        try makeSilentM4A(at: fileURL)

        let info = ExportMetadataProcessor.ExportInfo(
            trackID: "track-42",
            albumID: "album-7",
            artworkURL: URL(string: "https://example.com/art.jpg"),
            lyrics: nil,
            title: "Test",
            artistName: "Artist",
            albumName: nil,
        )
        try await ExportMetadataProcessor.embedExportMetadata(info, into: fileURL)

        let metadata = try await readMetadata(from: fileURL)
        let comment = try #require(metadata.filter { isComment($0) }.first, "Expected comment metadata")

        let commentString = await stringValue(of: comment)
        let data = commentString?.data(using: .utf8)
        let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        #expect(json?["v"] as? Int == 1)
        #expect(json?["trackID"] as? String == "track-42")
        #expect(json?["albumID"] as? String == "album-7")
        #expect(json?["artworkURL"] as? String == "https://example.com/art.jpg")
    }

    @Test
    func `embeds lyrics when provided`() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = dir.appendingPathComponent("test.m4a")
        try makeSilentM4A(at: fileURL)

        let lyrics = "[00:01.00]First line\n[00:05.00]Second line"
        let info = ExportMetadataProcessor.ExportInfo(
            trackID: "track-1",
            albumID: nil,
            artworkURL: nil,
            lyrics: lyrics,
            title: "Song",
            artistName: "Artist",
            albumName: nil,
        )
        try await ExportMetadataProcessor.embedExportMetadata(info, into: fileURL)

        let metadata = try await readMetadata(from: fileURL)
        let lyricsItem = try #require(metadata.filter { isLyrics($0) }.first, "Expected lyrics metadata")

        let value = await stringValue(of: lyricsItem)
        #expect(value == lyrics)
    }

    @Test
    func `omits lyrics metadata when lyrics is nil`() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = dir.appendingPathComponent("test.m4a")
        try makeSilentM4A(at: fileURL)

        let info = ExportMetadataProcessor.ExportInfo(
            trackID: "track-1",
            albumID: nil,
            artworkURL: nil,
            lyrics: nil,
            title: "Song",
            artistName: "Artist",
            albumName: nil,
        )
        try await ExportMetadataProcessor.embedExportMetadata(info, into: fileURL)

        let metadata = try await readMetadata(from: fileURL)
        let lyricsItems = metadata.filter { isLyrics($0) }
        #expect(lyricsItems.isEmpty, "Expected no lyrics metadata when nil")
    }

    @Test
    func `omits albumID and artworkURL from JSON when nil`() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = dir.appendingPathComponent("test.m4a")
        try makeSilentM4A(at: fileURL)

        let info = ExportMetadataProcessor.ExportInfo(
            trackID: "track-99",
            albumID: nil,
            artworkURL: nil,
            lyrics: nil,
            title: "Song",
            artistName: "Artist",
            albumName: nil,
        )
        try await ExportMetadataProcessor.embedExportMetadata(info, into: fileURL)

        let metadata = try await readMetadata(from: fileURL)
        let comment = try #require(metadata.filter { isComment($0) }.first, "Expected comment metadata")

        let commentString = await stringValue(of: comment)
        let data = commentString?.data(using: .utf8)
        let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        #expect(json?["trackID"] as? String == "track-99")
        #expect(json?["albumID"] == nil)
        #expect(json?["artworkURL"] == nil)
    }

    @Test
    func `minimal init embeds only trackID and albumID in JSON comment`() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = dir.appendingPathComponent("test.m4a")
        try makeSilentM4A(at: fileURL)

        let info = ExportMetadataProcessor.ExportInfo(trackID: "track-55", albumID: "album-12")
        try await ExportMetadataProcessor.embedExportMetadata(info, into: fileURL)

        let metadata = try await readMetadata(from: fileURL)

        let comment = try #require(metadata.filter { isComment($0) }.first, "Expected comment metadata")
        let commentString = await stringValue(of: comment)
        let data = commentString?.data(using: .utf8)
        let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        #expect(json?["v"] as? Int == 1)
        #expect(json?["trackID"] as? String == "track-55")
        #expect(json?["albumID"] as? String == "album-12")
        #expect(json?["artworkURL"] == nil)

        let lyricsItems = metadata.filter { isLyrics($0) }
        #expect(lyricsItems.isEmpty, "Expected no lyrics with minimal init")

        let titles = metadata.filter {
            $0.identifier == .commonIdentifierTitle || $0.identifier == .iTunesMetadataSongName
        }
        #expect(titles.isEmpty, "Expected no title with minimal init")
    }

    @Test
    func `verifyEmbeddedMetadata passes after successful embed with valid catalog IDs`() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = dir.appendingPathComponent("test.m4a")
        try makeSilentM4A(at: fileURL)

        let info = ExportMetadataProcessor.ExportInfo(
            trackID: "1692905594",
            albumID: "1692905593",
            artworkURL: URL(string: "https://example.com/art.jpg"),
            lyrics: nil,
            title: "Test Song",
            artistName: "Test Artist",
            albumName: "Test Album",
        )
        try await ExportMetadataProcessor.embedExportMetadata(info, into: fileURL)
        try await ExportMetadataProcessor.verifyEmbeddedMetadata(in: fileURL, expectedTrackID: "1692905594")
    }

    @Test
    func `verifyEmbeddedMetadata fails for file without comment metadata`() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = dir.appendingPathComponent("test.m4a")
        try makeSilentM4A(at: fileURL)

        await #expect(throws: (any Error).self) {
            try await ExportMetadataProcessor.verifyEmbeddedMetadata(in: fileURL, expectedTrackID: "1234567890")
        }
    }

    @Test
    func `throws fileUnreadable for nonexistent file`() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let missingURL = dir.appendingPathComponent("does_not_exist.m4a")
        let info = ExportMetadataProcessor.ExportInfo(trackID: "track-1", albumID: nil)

        await #expect(throws: (any Error).self) {
            try await ExportMetadataProcessor.embedExportMetadata(info, into: missingURL)
        }
    }

    @Test
    func `throws fileUnreadable for non-audio file`() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let textURL = dir.appendingPathComponent("not_audio.m4a")
        try Data("not an audio file".utf8).write(to: textURL)

        let info = ExportMetadataProcessor.ExportInfo(trackID: "track-1", albumID: nil)

        await #expect(throws: (any Error).self) {
            try await ExportMetadataProcessor.embedExportMetadata(info, into: textURL)
        }
    }

    @MainActor
    @Test
    func `import creates local track without retaining completed download job`() async throws {
        let sandbox = TestLibrarySandbox()
        let database = try makeImportDatabase(sandbox: sandbox)
        let paths = database.paths
        let downloadStore = DownloadStore(database: database, paths: paths)
        let metadataReader = EmbeddedMetadataReader()
        let indexer = SongLibraryIndexer(databaseManager: database.databaseManager)
        let apiClient = try APIClient(baseURL: #require(URL(string: "https://example.com")))
        let importer = AudioFileImporter(
            paths: paths,
            database: database,
            metadataReader: metadataReader,
            libraryIndexer: indexer,
            apiClient: apiClient,
        )

        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = dir.appendingPathComponent("imported-track.m4a")
        try makeSilentM4A(at: fileURL)

        let trackID = "1234567890"
        let albumID = "9876543210"
        let artworkURL = try #require(URL(string: "https://example.com/artwork.jpg"))
        let info = ExportMetadataProcessor.ExportInfo(
            trackID: trackID,
            albumID: albumID,
            artworkURL: artworkURL,
            lyrics: nil,
            title: "Imported Song",
            artistName: "Imported Artist",
            albumName: "Imported Album",
        )
        try await ExportMetadataProcessor.embedExportMetadata(info, into: fileURL)

        try Data([0xFF, 0xD8, 0xFF]).write(to: paths.artworkCacheURL(for: trackID))

        let result = await importer.importFiles(urls: [fileURL])

        #expect(result.succeeded == 1)
        #expect(result.duplicates == 0)
        #expect(result.noMetadata == 0)
        #expect(result.errors == 0)

        let relativePath = "\(albumID)/\(trackID).m4a"
        #expect(try database.downloadJob(trackID: trackID) == nil)
        #expect(downloadStore.hasRecord(trackID: trackID) == false)
        #expect(downloadStore.isDownloaded(trackID: trackID))

        let importedTrack = try #require(try database.track(byID: trackID))
        #expect(importedTrack.relativePath == relativePath)
        #expect(importedTrack.albumID == albumID)
        #expect(importedTrack.title == "Imported Song")
        #expect(importedTrack.artistName == "Imported Artist")
        #expect(importedTrack.albumTitle == "Imported Album")
    }

    @MainActor
    @Test
    func `imports ordinary m4a without MuseAmp comment metadata`() async throws {
        let sandbox = TestLibrarySandbox()
        let database = try makeImportDatabase(sandbox: sandbox)
        let importer = try makeImporter(database: database)
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = dir.appendingPathComponent("ordinary.m4a")
        let artworkData = tinyArtworkData()
        try makeSilentM4A(at: fileURL)
        try await embedPlainMetadata(
            into: fileURL,
            title: "Ordinary Song",
            artistName: "Ordinary Artist",
            albumName: "Ordinary Album",
            artworkData: artworkData,
        )

        let result = await importer.importFiles(urls: [fileURL])

        #expect(result.succeeded == 1)
        #expect(result.noMetadata == 0)
        #expect(result.errors == 0)

        let tracks = try database.allTracks()
        let importedTrack = try #require(tracks.first)
        #expect(importedTrack.trackID.isCatalogID)
        #expect(importedTrack.albumID.isCatalogID)
        #expect(importedTrack.title == "Ordinary Song")
        #expect(importedTrack.artistName == "Ordinary Artist")
        #expect(importedTrack.albumTitle == "Ordinary Album")
        #expect(importedTrack.hasEmbeddedArtwork)
        #expect(importedTrack.hasEmbeddedLyrics == false)
        #expect(try Data(contentsOf: database.paths.artworkCacheURL(for: importedTrack.trackID)) == artworkData)
    }

    @MainActor
    @Test
    func `imports m4a with missing display tags using fallbacks`() async throws {
        let sandbox = TestLibrarySandbox()
        let database = try sandbox.makeDatabase()
        let importer = try makeImporter(database: database)
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = dir.appendingPathComponent("fallback-title.m4a")
        try makeSilentM4A(at: fileURL)

        let result = await importer.importFiles(urls: [fileURL])

        #expect(result.succeeded == 1)
        #expect(result.noMetadata == 0)
        #expect(result.errors == 0)

        let importedTrack = try #require(try database.allTracks().first)
        #expect(importedTrack.title == "fallback-title")
        #expect(importedTrack.artistName == "Unknown Artist")
        #expect(importedTrack.albumTitle == "Unknown Album")
        #expect(importedTrack.trackID.isCatalogID)
        #expect(importedTrack.albumID.isCatalogID)
    }

    @MainActor
    @Test
    func `exported arbitrary m4a round trips with generated catalog IDs`() async throws {
        let sourceSandbox = TestLibrarySandbox()
        let sourceDatabase = try makeImportDatabase(sandbox: sourceSandbox)
        let sourceImporter = try makeImporter(database: sourceDatabase)
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = dir.appendingPathComponent("round-trip-source.m4a")
        try makeSilentM4A(at: fileURL)
        try await embedPlainMetadata(
            into: fileURL,
            title: "Round Trip Song",
            artistName: "Round Trip Artist",
            albumName: "Round Trip Album",
        )

        let sourceResult = await sourceImporter.importFiles(urls: [fileURL])
        #expect(sourceResult.succeeded == 1)
        let sourceTrack = try #require(try sourceDatabase.allTracks().first)

        let builder = SyncPreparedTrackBuilder(
            paths: sourceDatabase.paths,
            lyricsCacheStore: nil,
            apiClient: nil,
        )
        let batch = try await builder.prepareBatch(
            deviceName: "Test Device",
            items: [sourceTrack.exportItem(paths: sourceDatabase.paths)],
        )
        defer { builder.cleanup(batch: batch) }
        let exportedURL = try #require(batch.preparedURLs.first)
        try await ExportMetadataProcessor.verifyEmbeddedMetadata(in: exportedURL, expectedTrackID: sourceTrack.trackID)

        let destinationSandbox = TestLibrarySandbox()
        let destinationDatabase = try makeImportDatabase(sandbox: destinationSandbox)
        let destinationImporter = try makeImporter(database: destinationDatabase)
        let destinationResult = await destinationImporter.importFiles(
            urls: [exportedURL],
            options: .offlineTransfer,
        )

        #expect(destinationResult.succeeded == 1)
        #expect(destinationResult.noMetadata == 0)
        let roundTrippedTrack = try #require(try destinationDatabase.track(byID: sourceTrack.trackID))
        #expect(roundTrippedTrack.albumID == sourceTrack.albumID)
        #expect(roundTrippedTrack.title == "Round Trip Song")
        #expect(roundTrippedTrack.artistName == "Round Trip Artist")
        #expect(roundTrippedTrack.albumTitle == "Round Trip Album")
    }
}

struct DownloadArtworkProcessorTimeoutTests {
    @Test
    func `overall timeout returns promptly for non-cooperative work`() async {
        let startedAt = Date()

        do {
            try await DownloadArtworkProcessor.withOverallTimeout(seconds: 0.05) {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    DispatchQueue.global(qos: .utility).async {
                        Thread.sleep(forTimeInterval: 1)
                        continuation.resume()
                    }
                }
            }
            Issue.record("Expected timeout")
        } catch {
            #expect(Date().timeIntervalSince(startedAt) < 0.5)
        }
    }
}
