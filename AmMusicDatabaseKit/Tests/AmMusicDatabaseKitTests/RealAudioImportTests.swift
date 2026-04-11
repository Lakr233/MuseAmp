//
//  RealAudioImportTests.swift
//  AmMusicDatabaseKit
//
//  Created by @Lakr233 on 2026/04/11.
//

import AmMusicDatabaseKit
@preconcurrency import AVFoundation
import CoreMedia
import Foundation
import Testing

@Suite(.serialized)
struct RealAudioImportTests {
    @Test
    func `ingest stores metadata from real exported audio file`() async throws {
        let fixture = try DatabaseIntegrityFixture()
        defer { try? fixture.cleanup() }

        let manager = await fixture.makeManager(inspectAudioFile: { fileURL in
            try await makeRealAudioInspection(fileURL: fileURL)
        })
        try await manager.initialize()

        let incomingURL = fixture.rootURL.appendingPathComponent("real-import.m4a", isDirectory: false)
        try makeSilentM4A(at: incomingURL)

        let lyrics = "[00:01.00]Database line one\n[00:02.00]Database line two"
        let artworkData = try makeTinyArtworkData()
        try await embedMetadata(
            into: incomingURL,
            title: "Real Import Song",
            artistName: "Real Import Artist",
            albumName: "Real Import Album",
            lyrics: lyrics,
            artworkData: artworkData,
        )

        let result = try await manager.send(
            .ingestAudioFile(
                url: incomingURL,
                metadata: ImportedTrackMetadata(
                    trackID: "real-import-track",
                    albumID: "real-import-album",
                    title: "Real Import Song",
                    artistName: "Real Import Artist",
                    albumTitle: "Real Import Album",
                    sourceKind: .downloaded,
                ),
            ),
        )
        guard case let .ingestedTrack(record) = result else {
            Issue.record("Expected ingestedTrack result")
            return
        }

        #expect(record.trackID == "real-import-track")
        #expect(record.albumID == "real-import-album")
        #expect(record.title == "Real Import Song")
        #expect(record.artistName == "Real Import Artist")
        #expect(record.albumTitle == "Real Import Album")
        #expect(record.durationSeconds > 0)
        #expect(record.hasEmbeddedLyrics)
        #expect(record.hasEmbeddedArtwork)

        let storedTrack = try #require(try manager.track(trackID: "real-import-track"))
        #expect(storedTrack.relativePath == "real-import-album/real-import-track.m4a")
        #expect(storedTrack.durationSeconds > 0)
        #expect(storedTrack.hasEmbeddedLyrics)
        #expect(storedTrack.hasEmbeddedArtwork)

        let storedFileURL = fixture.paths.audioDirectory.appendingPathComponent(
            "real-import-album/real-import-track.m4a",
            isDirectory: false,
        )
        #expect(FileManager.default.fileExists(atPath: storedFileURL.path))

        let cachedLyrics = manager.lyricsCacheStore.lyrics(for: "real-import-track")
        #expect(cachedLyrics == lyrics)

        let artworkCacheURL = fixture.paths.artworkCacheURL(for: "real-import-track")
        #expect(FileManager.default.fileExists(atPath: artworkCacheURL.path))
        let cachedArtwork = try Data(contentsOf: artworkCacheURL)
        #expect(cachedArtwork == artworkData)
    }
}

private enum RealAudioImportTestError: Error {
    case fileUnreadable
    case exportSessionUnavailable
    case exportFailed
    case exportTimedOut
    case invalidArtworkData
}

private func makeSilentM4A(at url: URL) throws {
    let settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: 44100.0,
        AVNumberOfChannelsKey: 1,
        AVEncoderBitRateKey: 64000,
    ]
    let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
    let frameCount: AVAudioFrameCount = 44100
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
    buffer.frameLength = frameCount

    let audioFile = try AVAudioFile(
        forWriting: url,
        settings: settings,
        commonFormat: .pcmFormatFloat32,
        interleaved: false,
    )
    try audioFile.write(from: buffer)
}

private func makeTinyArtworkData() throws -> Data {
    let base64 =
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/a6sAAAAASUVORK5CYII="
    guard let data = Data(base64Encoded: base64) else {
        throw RealAudioImportTestError.invalidArtworkData
    }
    return data
}

private func embedMetadata(
    into fileURL: URL,
    title: String,
    artistName: String,
    albumName: String,
    lyrics: String,
    artworkData: Data,
) async throws {
    guard FileManager.default.isReadableFile(atPath: fileURL.path) else {
        throw RealAudioImportTestError.fileUnreadable
    }

    let asset = AVURLAsset(url: fileURL)
    guard await (try? asset.load(.isReadable)) == true else {
        throw RealAudioImportTestError.fileUnreadable
    }
    guard let exportSession = AVAssetExportSession(
        asset: asset,
        presetName: AVAssetExportPresetPassthrough,
    ) else {
        throw RealAudioImportTestError.exportSessionUnavailable
    }

    let tempURL = fileURL.deletingLastPathComponent()
        .appendingPathComponent(UUID().uuidString, isDirectory: false)
        .appendingPathExtension("m4a")

    exportSession.outputURL = tempURL
    exportSession.outputFileType = .m4a
    exportSession.shouldOptimizeForNetworkUse = false
    exportSession.metadata = [
        metadataItem(identifier: .commonIdentifierTitle, value: title),
        metadataItem(identifier: .commonIdentifierArtist, value: artistName),
        metadataItem(identifier: .commonIdentifierAlbumName, value: albumName),
        metadataItem(identifier: .iTunesMetadataLyrics, value: lyrics),
        artworkMetadataItem(data: artworkData),
    ]

    do {
        try await export(exportSession)
        _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: tempURL)
    } catch {
        if FileManager.default.fileExists(atPath: tempURL.path) {
            try? FileManager.default.removeItem(at: tempURL)
        }
        throw error
    }
}

private func makeRealAudioInspection(fileURL: URL) async throws -> AudioFileInspection {
    let asset = AVURLAsset(url: fileURL)
    let duration = try await asset.load(.duration)
    let items = try await collectMetadataItems(from: asset)

    let trackID = fileURL.deletingPathExtension().lastPathComponent
    let albumID = fileURL.deletingLastPathComponent().lastPathComponent
    let title = await stringValue(in: items, matching: ["title", "songname"]) ?? trackID
    let artistName = await stringValue(in: items, matching: ["artist"]) ?? "Unknown Artist"
    let albumName = await stringValue(in: items, matching: ["albumname", "album"]) ?? "Unknown Album"
    let lyrics = await stringValue(in: items, matching: ["lyrics", "lyr"])
    let artworkData = await artworkValue(in: items)

    return AudioFileInspection(
        metadata: ImportedTrackMetadata(
            trackID: trackID,
            albumID: albumID,
            title: title,
            artistName: artistName,
            albumTitle: albumName,
            durationSeconds: max(CMTimeGetSeconds(duration), 0),
            lyrics: lyrics,
            sourceKind: .downloaded,
        ),
        embeddedArtwork: artworkData,
    )
}

private func stringValue(in items: [AVMetadataItem], matching tokens: [String]) async -> String? {
    for item in items where matches(item, tokens: tokens) {
        if let value = try? await item.load(.stringValue)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        {
            return value
        }
        if let value = try? await item.load(.value) as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
    }
    return nil
}

private func artworkValue(in items: [AVMetadataItem]) async -> Data? {
    for item in items where matches(item, tokens: ["artwork", "coverart"]) {
        if let data = try? await item.load(.dataValue), !data.isEmpty {
            return data
        }
        if let data = try? await item.load(.value) as? Data, !data.isEmpty {
            return data
        }
    }
    return nil
}

private func matches(_ item: AVMetadataItem, tokens: [String]) -> Bool {
    let identifier = item.identifier?.rawValue.lowercased() ?? ""
    let commonKey = item.commonKey?.rawValue.lowercased() ?? ""
    let key =
        (item.key as? String)?.lowercased()
            ?? (item.key as? NSString)?.lowercased
            ?? ""
    return tokens.contains { token in
        identifier.contains(token) || commonKey.contains(token) || key.contains(token)
    }
}

private func metadataItem(identifier: AVMetadataIdentifier, value: String) -> AVMetadataItem {
    let item = AVMutableMetadataItem()
    item.identifier = identifier
    item.value = value as NSString
    return item.copy() as! AVMetadataItem
}

private func artworkMetadataItem(data: Data) -> AVMetadataItem {
    let item = AVMutableMetadataItem()
    item.identifier = .commonIdentifierArtwork
    item.value = data as NSData
    item.dataType = kCMMetadataBaseDataType_PNG as String
    return item.copy() as! AVMetadataItem
}

private func collectMetadataItems(from asset: AVURLAsset) async throws -> [AVMetadataItem] {
    var items = try await asset.load(.commonMetadata)
    let formats = try await asset.load(.availableMetadataFormats)
    for format in formats {
        try await items.append(contentsOf: asset.loadMetadata(for: format))
    }
    return items
}

private func export(_ exportSession: AVAssetExportSession) async throws {
    let sessionBox = ExportSessionBox(exportSession)
    try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, any Error>) in
        sessionBox.session.exportAsynchronously {
            switch sessionBox.session.status {
            case .completed:
                continuation.resume()
            case .failed:
                continuation.resume(throwing: sessionBox.session.error ?? RealAudioImportTestError.exportFailed)
            case .cancelled:
                continuation.resume(throwing: sessionBox.session.error ?? CancellationError())
            default:
                continuation.resume(throwing: sessionBox.session.error ?? RealAudioImportTestError.exportFailed)
            }
        }
    }
}

private final class ExportSessionBox: @unchecked Sendable {
    let session: AVAssetExportSession

    init(_ session: AVAssetExportSession) {
        self.session = session
    }
}
