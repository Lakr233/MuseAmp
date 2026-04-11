@testable import AmMusic
import AmMusicDatabaseKit
@preconcurrency import AVFoundation
import Foundation
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
    func `prepare batch for transfer skips metadata embedding`() async throws {
        let sandbox = TestLibrarySandbox()
        let environment = sandbox.makeEnvironment()
        let builder = SyncPreparedTrackBuilder(
            paths: environment.paths,
        )

        let sourceURL = sandbox.baseDirectory.appendingPathComponent("source.m4a")
        try makeSilentM4A(at: sourceURL)

        let track = AudioTrackRecord(
            trackID: "1234567890",
            albumID: "9988776655",
            fileExtension: "m4a",
            relativePath: "source.m4a",
            fileSizeBytes: 0,
            fileModifiedAt: Date(),
            durationSeconds: 1.0,
            title: "Song",
            artistName: "Artist",
            albumTitle: "Album",
        )

        let batch = try await builder.prepareBatch(
            deviceName: "Device",
            tracks: [track],
        )
        defer { builder.cleanup(batch: batch) }

        #expect(batch.manifest.deviceName == "Device")
        #expect(batch.manifest.entries.count == 1)

        let entry = try #require(batch.manifest.entries.first)
        #expect(entry.trackID == "1234567890")
        #expect(entry.durationSeconds == 1.0)
        #expect(batch.filesByTrackID["1234567890"] != nil)
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
        let frameCount: AVAudioFrameCount = 44100
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
}
