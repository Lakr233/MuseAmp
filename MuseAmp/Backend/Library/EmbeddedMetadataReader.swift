//
//  EmbeddedMetadataReader.swift
//  MuseAmp
//
//  Created by @Lakr233 on 2026/04/11.
//

import AVFoundation
import Foundation
import MuseAmpDatabaseKit

enum EmbeddedMetadataReaderError: Error {
    case unableToLoadMetadata
}

final nonisolated class EmbeddedMetadataReader: @unchecked Sendable {
    func extractArtwork(from fileURL: URL) async -> Data? {
        let asset = AVURLAsset(url: fileURL)
        guard let items = try? await asset.load(.commonMetadata) else {
            AppLog.warning(self, "extractArtwork unable to load commonMetadata for '\(fileURL.path)'")
            return nil
        }
        for item in items {
            let identifier = item.identifier?.rawValue.lowercased() ?? ""
            let commonKey = item.commonKey?.rawValue.lowercased() ?? ""
            let key = (item.key as? String)?.lowercased() ?? (item.key as? NSString)?.lowercased ?? ""
            let isArtwork = ["artwork", "coverart"].contains { token in
                identifier.contains(token) || commonKey.contains(token) || key.contains(token)
            }
            guard isArtwork else { continue }
            if let data = try? await item.load(.dataValue), !data.isEmpty {
                return data
            }
            if let value = try? await item.load(.value) as? Data, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    func extractLyrics(from metadataItems: [AVMetadataItem]) async -> String? {
        nonisolated(unsafe) let items = metadataItems
        return await lyricsStringValue(in: items)
    }

    func makeTrackRecord(
        fileURL: URL,
        relativePath: String,
        trackID: String,
        albumID: String?,
        fileSize: Int64,
        modifiedAt: Date,
    ) async throws -> AudioTrackRecord {
        try validateFileIsReadable(at: fileURL)
        let asset = AVURLAsset(url: fileURL)
        let durationSeconds = try await validatePlayability(of: asset, fileURL: fileURL)
        let metadataItems = try await collectMetadataItems(from: asset)
        let fileName = fileURL.deletingPathExtension().lastPathComponent
        let title = await stringValue(in: metadataItems, matching: ["title", "songName"]) ?? fileName
        let artist = await stringValue(in: metadataItems, matching: ["artist"]) ?? String(localized: "Unknown Artist")
        let album = await stringValue(in: metadataItems, matching: ["albumName", "album"]) ?? String(localized: "Unknown Album")

        let albumArtist = await stringValue(in: metadataItems, matching: ["albumArtist"])
        let trackNumber = await AVMetadataHelper.integerValue(
            in: metadataItems,
            matching: ["trackNumber", "track", "trk", "trkn", "trck", "albumAndTrack"],
        )
        let discNumber = await AVMetadataHelper.integerValue(
            in: metadataItems,
            matching: ["discNumber", "disc", "disk", "tpos"],
        )
        let genre = await stringValue(in: metadataItems, matching: ["genre"])
        let composer = await stringValue(in: metadataItems, matching: ["composer", "creator"])
        let releaseDate = await releaseDate(in: metadataItems)
        let hasEmbeddedLyrics = await hasStringMetadata(in: metadataItems, matching: ["lyrics"])
        let hasEmbeddedArtwork = await hasArtwork(in: metadataItems)

        return AudioTrackRecord(
            trackID: trackID,
            albumID: albumID ?? "unknown",
            fileExtension: fileURL.pathExtension,
            relativePath: relativePath,
            fileSizeBytes: fileSize,
            fileModifiedAt: modifiedAt,
            durationSeconds: durationSeconds,
            title: title,
            artistName: artist,
            albumTitle: album,
            albumArtistName: albumArtist,
            trackNumber: trackNumber,
            discNumber: discNumber,
            genreName: genre,
            composerName: composer,
            releaseDate: releaseDate,
            hasEmbeddedLyrics: hasEmbeddedLyrics,
            hasEmbeddedArtwork: hasEmbeddedArtwork,
            sourceKind: .unknown,
            createdAt: .init(),
            updatedAt: .init(),
        )
    }
}

private nonisolated extension EmbeddedMetadataReader {
    /// Opens the file and reads a leading chunk so that pure I/O problems
    /// (missing file, locked file protection) surface as non-validation errors
    /// before any playability verdict is made. Only a successfully opened but
    /// empty file is a deterministic validation failure.
    func validateFileIsReadable(at fileURL: URL) throws {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        let probe = try handle.read(upToCount: 4096)
        guard let probe, !probe.isEmpty else {
            throw AudioFileValidationError.unreadable(reason: "file is empty")
        }
    }

    func validatePlayability(of asset: AVURLAsset, fileURL: URL) async throws -> TimeInterval {
        let isPlayable: Bool
        let duration: CMTime
        do {
            (isPlayable, duration) = try await asset.load(.isPlayable, .duration)
        } catch {
            // The readability probe already passed, so a load failure means the
            // container is not decodable rather than a transient I/O problem.
            AppLog.error(self, "asset properties failed to load for '\(fileURL.lastPathComponent)': \(error.localizedDescription)")
            throw AudioFileValidationError.notPlayable(reason: error.localizedDescription)
        }
        guard isPlayable else {
            AppLog.error(self, "asset is not playable '\(fileURL.lastPathComponent)'")
            throw AudioFileValidationError.notPlayable(reason: "AVURLAsset reports the file is not playable")
        }
        let durationSeconds = CMTimeGetSeconds(duration)
        guard AudioFileValidationError.isDurationValid(durationSeconds) else {
            AppLog.error(self, "asset duration \(durationSeconds)s out of range '\(fileURL.lastPathComponent)'")
            throw AudioFileValidationError.durationOutOfRange(durationSeconds)
        }
        return durationSeconds
    }

    func collectMetadataItems(from asset: AVURLAsset) async throws -> [AVMetadataItem] {
        try await AVMetadataHelper.collectMetadataItems(from: asset)
    }

    func stringValue(in items: [AVMetadataItem], matching tokens: [String]) async -> String? {
        let loweredTokens = tokens.map { $0.lowercased() }
        for item in items {
            guard matches(item: item, tokens: loweredTokens) else { continue }
            if let value = try? await item.load(.stringValue)?.trimmingCharacters(in: .whitespacesAndNewlines),
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

    func releaseDate(in items: [AVMetadataItem]) async -> String? {
        if let value = await stringValue(in: items, matching: ["releaseDate", "creationDate", "date"]) {
            return value
        }

        for item in items {
            guard matches(item: item, tokens: ["creationdate", "releasedate", "date"]) else { continue }
            if let date = try? await item.load(.dateValue) {
                return ISO8601DateFormatter().string(from: date)
            }
        }
        return nil
    }

    func hasStringMetadata(in items: [AVMetadataItem], matching tokens: [String]) async -> Bool {
        await stringValue(in: items, matching: tokens) != nil
    }

    func lyricsStringValue(in items: [AVMetadataItem]) async -> String? {
        for item in items {
            guard item.identifier == .iTunesMetadataLyrics
                || matches(item: item, tokens: ["lyrics", "lyr"])
            else { continue }
            if let value = try? await item.load(.stringValue)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !value.isEmpty
            {
                return value
            }
        }
        return nil
    }

    func hasArtwork(in items: [AVMetadataItem]) async -> Bool {
        for item in items {
            if matches(item: item, tokens: ["artwork", "coverart"]) {
                let hasData = await (try? item.load(.dataValue)) != nil
                let hasValue = await (try? item.load(.value)) != nil
                if hasData || hasValue {
                    return true
                }
            }
        }
        return false
    }

    func matches(item: AVMetadataItem, tokens: [String]) -> Bool {
        AVMetadataHelper.matches(item, tokens: tokens)
    }
}
