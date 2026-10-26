@preconcurrency import AVFoundation
import CoreMedia
import Foundation
@testable import MuseAmp
import MuseAmpDatabaseKit
import Testing

@Suite(.serialized)
@MainActor
struct AudioFileImporterTests {
    @Test
    func `fallback imports tagged M4A without modifying the source or its tags`() async throws {
        let sandbox = TestLibrarySandbox()
        let (database, importer) = try makeImporter(in: sandbox)
        let source = try await makeFile(in: sandbox, comment: "Original liner notes")
        let originalBytes = try Data(contentsOf: source)
        let expected = try EmbeddedTrackIdentity.local(fileURL: source, album: "Album", albumArtist: "Album Artist", artist: "Artist")

        let result = await importer.importFiles(urls: [source], options: .offlineTransfer)

        #expect(result.succeeded == 1)
        #expect(result.errors == 0)
        #expect(result.noMetadata == 0)
        #expect(try Data(contentsOf: source) == originalBytes)
        let record = try #require(try database.track(byID: expected.trackID))
        #expect(record.albumID == expected.albumID)
        #expect(record.title == "Song")
        #expect(record.artistName == "Artist")
        #expect(record.albumArtistName == "Album Artist")
        #expect(record.trackNumber == 3)
        #expect(record.discNumber == 2)
        #expect(record.sourceKind == .imported)
        #expect(try database.downloadJob(trackID: record.trackID) == nil)
        let stored = database.paths.absoluteAudioURL(for: record.relativePath)
        try await ExportMetadataProcessor.verifyEmbeddedMetadata(in: stored, expectedTrackID: expected.trackID, expectedAlbumID: expected.albumID)
        let reader = EmbeddedMetadataReader()
        #expect(await reader.extractArtwork(from: stored) == artwork)
        #expect(await EmbeddedLyricsReader.lyrics(fromFileAt: stored) == "[00:01.00]Original lyrics")
        #expect(try await commentPayload(at: stored)["originalComments"] as? [String] == ["Original liner notes"])
        #expect(try FileManager.default.contentsOfDirectory(atPath: database.paths.incomingDirectory.path).isEmpty)
    }

    @Test(arguments: [
        #"Use "trackID" for reference"#, #"{"albumID":"third-party-id"}"#,
        #"{"v":1,"albumID":"third-party-id"}"#,
    ])
    func `fallback preserves ordinary comments mentioning identity fields`(_ comment: String) async throws {
        let sandbox = TestLibrarySandbox()
        let (database, importer) = try makeImporter(in: sandbox)
        let source = try await makeFile(in: sandbox, comment: comment)
        let result = await importer.importFiles(urls: [source], options: .offlineTransfer)
        #expect(result.succeeded == 1)
        let track = try #require(try database.allTracks().first)
        let stored = database.paths.absoluteAudioURL(for: track.relativePath)
        let payload = try await commentPayload(at: stored)
        #expect(payload["source"] as? String == EmbeddedTrackIdentity.source)
        #expect(payload["originalComments"] as? [String] == [comment])
    }

    @Test
    func `fallback accepts absent comments and deduplicates renamed originals`() async throws {
        let sandbox = TestLibrarySandbox()
        let (database, importer) = try makeImporter(in: sandbox)
        let source = try await makeFile(in: sandbox)
        let first = await importer.importFiles(urls: [source, source], options: .offlineTransfer)
        #expect(first.succeeded == 1)
        #expect(first.duplicates == 1)
        let renamed = sandbox.baseDirectory.appendingPathComponent("renamed.m4a")
        try FileManager.default.moveItem(at: source, to: renamed)
        let second = await importer.importFiles(urls: [renamed], options: .offlineTransfer)
        #expect(second.duplicates == 1)
        #expect(try database.allTracks().count == 1)
    }

    @Test
    func `existing catalog comments preserve their original IDs and file bytes`() async throws {
        let sandbox = TestLibrarySandbox()
        let (database, importer) = try makeImporter(in: sandbox)
        let source = try await makeFile(in: sandbox, comment: #"{"v":1,"trackID":"123","albumID":"456"}"#)
        let originalBytes = try Data(contentsOf: source)
        let result = await importer.importFiles(urls: [source], options: .offlineTransfer)
        #expect(result.succeeded == 1)
        let record = try #require(try database.track(byID: "123"))
        #expect(record.albumID == "456")
        #expect(try Data(contentsOf: database.paths.absoluteAudioURL(for: record.relativePath)) == originalBytes)
    }

    @Test(arguments: [
        #"{"source":"MuseAmp","v":1,"trackID":"123"}"#,
        #"{"v":2,"trackID":"123","albumID":"456"}"#,
        #"{"source":"MuseAmp","v":1,"trackID":"123","albumID":"456""#,
    ])
    func `invalid identity is rejected without fallback or staging files`(_ comment: String) async throws {
        let sandbox = TestLibrarySandbox()
        let (database, importer) = try makeImporter(in: sandbox)
        let source = try await makeFile(in: sandbox, comment: comment)
        let originalBytes = try Data(contentsOf: source)
        let result = await importer.importFiles(urls: [source], options: .offlineTransfer)
        #expect(result.errors == 1)
        #expect(result.succeeded == 0)
        #expect(try database.allTracks().isEmpty)
        #expect(try Data(contentsOf: source) == originalBytes)
        #expect(try FileManager.default.contentsOfDirectory(atPath: database.paths.incomingDirectory.path).isEmpty)
    }

    @Test(arguments: [true, false])
    func `fallback still requires title and artist`(_ missingTitle: Bool) async throws {
        let sandbox = TestLibrarySandbox()
        let (database, importer) = try makeImporter(in: sandbox)
        let source = try await makeFile(in: sandbox, title: missingTitle ? nil : "Song", artist: missingTitle ? "Artist" : nil)
        let result = await importer.importFiles(urls: [source], options: .offlineTransfer)
        #expect(result.noMetadata == 1)
        #expect(result.succeeded == 0)
        #expect(try database.allTracks().isEmpty)
    }

    @Test
    func `local IDs and comments survive transfer reembed and reimport`() async throws {
        let sandbox = TestLibrarySandbox()
        let (database, importer) = try makeImporter(in: sandbox)
        let source = try await makeFile(in: sandbox, comment: "Original notes")
        let imported = await importer.importFiles(urls: [source], options: .offlineTransfer)
        #expect(imported.succeeded == 1)
        let track = try #require(try database.allTracks().first)
        let stored = database.paths.absoluteAudioURL(for: track.relativePath)
        let builder = SyncPreparedTrackBuilder(paths: database.paths)
        #expect(await builder.sourceHasCatalogComment(at: stored, expectedTrackID: track.trackID))
        let batch = try await builder.prepareBatch(deviceName: "Test", tracks: [track], includeLyrics: true)
        defer { builder.cleanup(batch: batch) }
        #expect(batch.manifest.protocolVersion == SyncConstants.localIdentityProtocolVersion)
        #expect(!SyncConstants.isCompatible(protocolVersion: "4", entries: batch.manifest.entries))
        let transferred = try #require(batch.filesByTrackID[track.trackID])
        #expect(await EmbeddedLyricsReader.lyrics(fromFileAt: transferred) == "[00:01.00]Original lyrics")
        #expect(try await commentPayload(at: transferred)["originalComments"] as? [String] == ["Original notes"])

        let receiver = TestLibrarySandbox()
        let (receivedDatabase, receivingImporter) = try makeImporter(in: receiver)
        let result = await receivingImporter.importFiles(urls: [transferred], options: .offlineTransfer)
        #expect(result.succeeded == 1)
        let received = try #require(try receivedDatabase.track(byID: track.trackID))
        #expect(received.albumID == track.albumID)
        #expect(received.title == track.title)
    }

    @Test
    func `reembed preserves unknown identity fields and verification checks both IDs`() async throws {
        let sandbox = TestLibrarySandbox()
        let source = try await makeFile(in: sandbox, comment: #"{"v":1,"trackID":"123","albumID":"456","custom":"keep"}"#)
        let info = ExportMetadataProcessor.ExportInfo(trackID: "123", albumID: "456")
        try await ExportMetadataProcessor.embedExportMetadata(info, into: source, preservingExistingTags: true)
        #expect(try await commentPayload(at: source)["custom"] as? String == "keep")
        await #expect(throws: (any Error).self) {
            try await ExportMetadataProcessor.verifyEmbeddedMetadata(in: source, expectedTrackID: "999")
        }
        await #expect(throws: (any Error).self) {
            try await ExportMetadataProcessor.verifyEmbeddedMetadata(in: source, expectedTrackID: "123", expectedAlbumID: "999")
        }
    }

    @Test
    func `a replaced picker file cannot change the staged identity or imported tags`() async throws {
        let sandbox = TestLibrarySandbox()
        let (database, importer) = try makeImporter(in: sandbox)
        let source = try await makeFile(in: sandbox, title: "Original")
        let replacement = try await makeFile(in: sandbox, title: "Replacement")
        let originalBytes = try Data(contentsOf: source)
        let expected = try EmbeddedTrackIdentity.local(fileURL: source, album: "Album", albumArtist: "Album Artist", artist: "Artist")
        try await importer.withStagedFile(from: source) { staged in
            _ = try FileManager.default.replaceItemAt(source, withItemAt: replacement)
            #expect(try Data(contentsOf: staged) == originalBytes)
            #expect(try Data(contentsOf: source) != originalBytes)
            let result = await importer.importFiles(urls: [staged], options: .offlineTransfer)
            #expect(result.succeeded == 1)
        }
        let record = try #require(try database.track(byID: expected.trackID))
        #expect(record.title == "Original")
        #expect(record.albumID == expected.albumID)
        #expect(try FileManager.default.contentsOfDirectory(atPath: database.paths.incomingDirectory.path).isEmpty)
    }

    @Test
    func `local identity and embedded metadata survive a real library rebuild`() async throws {
        let sandbox = TestLibrarySandbox()
        let (database, importer) = try makeImporter(in: sandbox)
        let source = try await makeFile(in: sandbox)
        let imported = await importer.importFiles(urls: [source], options: .offlineTransfer)
        #expect(imported.succeeded == 1)
        let original = try #require(try database.allTracks().first)
        let indexer = SongLibraryIndexer(databaseManager: database.databaseManager)
        let result = try await indexer.syncLibrary(forceArtwork: true)
        #expect(result.removedInvalidFiles.isEmpty)
        let rebuilt = try #require(try database.track(byID: original.trackID))
        #expect(rebuilt.albumID == original.albumID)
        #expect(rebuilt.title == original.title)
        #expect(rebuilt.trackNumber == 3)
        #expect(rebuilt.discNumber == 2)
        #expect(rebuilt.hasEmbeddedArtwork)
        let stored = database.paths.absoluteAudioURL(for: rebuilt.relativePath)
        #expect(await EmbeddedMetadataReader().extractArtwork(from: stored) == artwork)
        #expect(await EmbeddedLyricsReader.lyrics(fromFileAt: stored) == "[00:01.00]Original lyrics")
    }

    @Test
    func `failed ingest cleans its staged fallback copy and keeps the source`() async throws {
        let sandbox = TestLibrarySandbox()
        let database = try sandbox.makeDatabase { _ in
            throw AudioFileValidationError.notPlayable(reason: "Injected inspection failure")
        }
        let importer = makeImporter(database: database)
        let source = try await makeFile(in: sandbox)
        let originalBytes = try Data(contentsOf: source)
        let result = await importer.importFiles(urls: [source], options: .offlineTransfer)
        #expect(result.errors == 1)
        #expect(result.succeeded == 0)
        #expect(try database.allTracks().isEmpty)
        #expect(try Data(contentsOf: source) == originalBytes)
        #expect(try FileManager.default.contentsOfDirectory(atPath: database.paths.incomingDirectory.path).isEmpty)
    }
}

private extension AudioFileImporterTests {
    var artwork: Data {
        Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/a6sAAAAASUVORK5CYII=")!
    }

    nonisolated static func inspectFile(_ fileURL: URL) async throws -> AudioFileInspection {
        let reader = EmbeddedMetadataReader()
        let trackID = fileURL.deletingPathExtension().lastPathComponent
        let albumID = fileURL.deletingLastPathComponent().lastPathComponent
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let record = try await reader.makeTrackRecord(
            fileURL: fileURL, relativePath: "\(albumID)/\(fileURL.lastPathComponent)",
            trackID: trackID, albumID: albumID,
            fileSize: (attributes[.size] as? NSNumber)?.int64Value ?? 0,
            modifiedAt: attributes[.modificationDate] as? Date ?? .init(),
        )
        return await AudioFileInspection(
            metadata: ImportedTrackMetadata(
                trackID: trackID, albumID: albumID, title: record.title,
                artistName: record.artistName, albumTitle: record.albumTitle,
                albumArtistName: record.albumArtistName, durationSeconds: record.durationSeconds,
                trackNumber: record.trackNumber, discNumber: record.discNumber,
                lyrics: EmbeddedLyricsReader.lyrics(fromFileAt: fileURL), sourceKind: .unknown,
            ),
            embeddedArtwork: reader.extractArtwork(from: fileURL),
        )
    }

    func makeImporter(in sandbox: TestLibrarySandbox) throws -> (MusicLibraryDatabase, AudioFileImporter) {
        let database = try sandbox.makeDatabase(inspectAudioFile: Self.inspectFile)
        return (database, makeImporter(database: database))
    }

    func makeImporter(database: MusicLibraryDatabase) -> AudioFileImporter {
        AudioFileImporter(
            paths: database.paths,
            database: database,
            metadataReader: EmbeddedMetadataReader(),
            apiClient: APIClient(baseURL: URL(string: "https://example.invalid")!),
        )
    }

    func commentPayload(at url: URL) async throws -> [String: Any] {
        let items = try await AVMetadataHelper.collectMetadataItems(from: AVURLAsset(url: url))
        for item in items where AVMetadataHelper.isComment(item) {
            if let value = try await item.load(.stringValue),
               let payload = try EmbeddedTrackIdentity.payload(from: value)
            {
                return payload
            }
        }
        throw EmbeddedTrackIdentity.IdentityError.invalidComment
    }

    func makeFile(
        in sandbox: TestLibrarySandbox,
        comment: String? = nil,
        title: String? = "Song",
        artist: String? = "Artist",
    ) async throws -> URL {
        let source = try sandbox.makeIncomingAudioFile()
        let asset = AVURLAsset(url: source)
        let session = try #require(AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough))
        var items: [AVMetadataItem] = []
        let strings: [(AVMetadataIdentifier, String?)] = [
            (.iTunesMetadataSongName, title), (.iTunesMetadataArtist, artist),
            (.iTunesMetadataAlbum, "Album"), (.iTunesMetadataAlbumArtist, artist == nil ? nil : "Album Artist"),
            (.iTunesMetadataLyrics, "[00:01.00]Original lyrics"), (.iTunesMetadataUserComment, comment),
        ]
        for (identifier, value) in strings {
            guard let value else { continue }
            let item = AVMutableMetadataItem()
            item.identifier = identifier
            item.value = value as NSString
            items.append(item.copy() as! AVMetadataItem)
        }
        for (identifier, position, count) in [(AVMetadataIdentifier.iTunesMetadataTrackNumber, 3, 8), (.iTunesMetadataDiscNumber, 2, 6)] {
            let item = AVMutableMetadataItem()
            item.identifier = identifier
            var bytes = [UInt8](repeating: 0, count: count)
            bytes[3] = UInt8(position)
            item.value = Data(bytes) as NSData
            item.dataType = kCMMetadataBaseDataType_RawData as String
            items.append(item.copy() as! AVMetadataItem)
        }
        let cover = AVMutableMetadataItem()
        cover.identifier = .iTunesMetadataCoverArt
        cover.value = artwork as NSData
        cover.dataType = kCMMetadataBaseDataType_PNG as String
        items.append(cover.copy() as! AVMetadataItem)
        session.metadata = items
        let output = sandbox.baseDirectory.appendingPathComponent("\(UUID().uuidString).m4a")
        session.outputURL = output
        session.outputFileType = .m4a
        try await DownloadArtworkProcessor.export(session, timeout: 30)
        _ = try FileManager.default.replaceItemAt(source, withItemAt: output)
        return source
    }
}
