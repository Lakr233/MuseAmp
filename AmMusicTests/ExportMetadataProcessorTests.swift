@testable import AmMusic
import AmMusicDatabaseKit
@preconcurrency import AVFoundation
import Dispatch
import Foundation
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

    // MARK: - Tests

    @Test("embeds title, artist, and album metadata")
    func embedsStandardMetadata() async throws {
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
            albumName: "Multiply"
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

    @Test("embeds JSON comment with trackID, albumID, artworkURL")
    func embedsJSONComment() async throws {
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
            albumName: nil
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

    @Test("embeds lyrics when provided")
    func embedsLyrics() async throws {
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
            albumName: nil
        )
        try await ExportMetadataProcessor.embedExportMetadata(info, into: fileURL)

        let metadata = try await readMetadata(from: fileURL)
        let lyricsItem = try #require(metadata.filter { isLyrics($0) }.first, "Expected lyrics metadata")

        let value = await stringValue(of: lyricsItem)
        #expect(value == lyrics)
    }

    @Test("omits lyrics metadata when lyrics is nil")
    func omitsLyricsWhenNil() async throws {
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
            albumName: nil
        )
        try await ExportMetadataProcessor.embedExportMetadata(info, into: fileURL)

        let metadata = try await readMetadata(from: fileURL)
        let lyricsItems = metadata.filter { isLyrics($0) }
        #expect(lyricsItems.isEmpty, "Expected no lyrics metadata when nil")
    }

    @Test("omits albumID and artworkURL from JSON when nil")
    func omitsOptionalJSONFields() async throws {
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
            albumName: nil
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

    @Test("minimal init embeds only trackID and albumID in JSON comment")
    func minimalInitEmbedsIDs() async throws {
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

    @Test("verifyEmbeddedMetadata passes after successful embed with valid catalog IDs")
    func verifyEmbeddedMetadataPasses() async throws {
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
            albumName: "Test Album"
        )
        try await ExportMetadataProcessor.embedExportMetadata(info, into: fileURL)
        try await ExportMetadataProcessor.verifyEmbeddedMetadata(in: fileURL, expectedTrackID: "1692905594")
    }

    @Test("verifyEmbeddedMetadata fails for file without comment metadata")
    func verifyEmbeddedMetadataFailsWithoutComment() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = dir.appendingPathComponent("test.m4a")
        try makeSilentM4A(at: fileURL)

        await #expect(throws: (any Error).self) {
            try await ExportMetadataProcessor.verifyEmbeddedMetadata(in: fileURL, expectedTrackID: "1234567890")
        }
    }

    @Test("throws fileUnreadable for nonexistent file")
    func throwsForNonexistentFile() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let missingURL = dir.appendingPathComponent("does_not_exist.m4a")
        let info = ExportMetadataProcessor.ExportInfo(trackID: "track-1", albumID: nil)

        await #expect(throws: (any Error).self) {
            try await ExportMetadataProcessor.embedExportMetadata(info, into: missingURL)
        }
    }

    @Test("throws fileUnreadable for non-audio file")
    func throwsForNonAudioFile() async throws {
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
    @Test("import creates local track without retaining completed download job")
    func importCreatesLocalTrackWithoutCompletedDownloadJob() async throws {
        let sandbox = TestLibrarySandbox()
        let database = try sandbox.makeDatabase()
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
            apiClient: apiClient
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
            albumName: "Imported Album"
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
}

struct DownloadArtworkProcessorTimeoutTests {
    @Test("overall timeout returns promptly for non-cooperative work")
    func overallTimeoutReturnsPromptly() async {
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
