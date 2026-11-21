//
//  ExportMetadataProcessor.swift
//  MuseAmp
//
//  Created by @Lakr233 on 2026/04/11.
//

@preconcurrency import AVFoundation
import Foundation
import MuseAmpDatabaseKit

enum ExportMetadataProcessor {
    nonisolated struct ExportInfo {
        let trackID: String
        let albumID: String?
        var artworkURL: URL?
        var artworkData: Data?
        var lyrics: String?
        var title: String?
        var artistName: String?
        var albumName: String?
        /// Written as the M4A `aART` atom, which is where
        /// `EmbeddedMetadataReader` reads it back. When nil, the file keeps
        /// whatever album artist it already has.
        var albumArtistName: String?
        /// Written as the M4A `trkn` / `disk` atoms, only when the file has
        /// no track or disc number of its own, so a total it carries is kept.
        var trackNumber: Int?
        var discNumber: Int?

        init(trackID: String, albumID: String?) {
            self.trackID = trackID
            self.albumID = albumID
        }

        init(
            trackID: String,
            albumID: String?,
            artworkURL: URL?,
            artworkData: Data? = nil,
            lyrics: String?,
            title: String?,
            artistName: String?,
            albumName: String?,
        ) {
            self.trackID = trackID
            self.albumID = albumID
            self.artworkURL = artworkURL
            self.artworkData = artworkData
            self.lyrics = lyrics
            self.title = title
            self.artistName = artistName
            self.albumName = albumName
        }
    }

    private nonisolated static let logger = "ExportMetadataProcessor"

    static func embedExportMetadata(
        _ info: ExportInfo,
        into fileURL: URL,
        timeout: TimeInterval = 30,
        preservingExistingTags: Bool = false,
    ) async throws {
        try await DownloadArtworkProcessor.withOverallTimeout(seconds: timeout) {
            try await performEmbedExportMetadata(
                info,
                into: fileURL,
                timeout: timeout,
                preservingExistingTags: preservingExistingTags,
            )
        }
    }

    /// Validates that the ExportInfo has all required fields for a complete
    /// metadata embed (trackID, albumID, title, artistName must be present).
    nonisolated static func validateExportInfo(_ info: ExportInfo) throws {
        guard EmbeddedTrackIdentity.isTrackID(info.trackID) else {
            AppLog.error(logger, "validateExportInfo invalid trackID='\(info.trackID)'")
            throw ExportError.invalidTrackID(info.trackID)
        }
        guard let albumID = info.albumID, EmbeddedTrackIdentity.isAlbumID(albumID) else {
            AppLog.error(logger, "validateExportInfo missing or invalid albumID trackID=\(info.trackID) albumID='\(info.albumID ?? "nil")'")
            throw ExportError.invalidAlbumID(info.trackID, info.albumID)
        }
        guard let title = info.title, !title.isEmpty else {
            AppLog.error(logger, "validateExportInfo missing title trackID=\(info.trackID)")
            throw ExportError.missingTitle(info.trackID)
        }
        guard let artist = info.artistName, !artist.isEmpty else {
            AppLog.error(logger, "validateExportInfo missing artistName trackID=\(info.trackID)")
            throw ExportError.missingArtist(info.trackID)
        }
        AppLog.verbose(logger, "validateExportInfo passed trackID=\(info.trackID) albumID=\(albumID) title='\(sanitizedLogText(title, maxLength: 40))' artist='\(sanitizedLogText(artist, maxLength: 40))'")
    }

    /// Reads the identity back instead of trusting that an export retained it.
    static func verifyEmbeddedMetadata(
        in fileURL: URL,
        expectedTrackID: String,
        expectedAlbumID: String? = nil,
    ) async throws {
        let items = try await AVMetadataHelper.collectMetadataItems(from: AVURLAsset(url: fileURL))
        guard let identity = try await EmbeddedTrackIdentity.read(from: items),
              identity.trackID == expectedTrackID,
              expectedAlbumID == nil || identity.albumID == expectedAlbumID
        else {
            AppLog.error(logger, "verifyEmbeddedMetadata missing or mismatched identity trackID=\(expectedTrackID)")
            throw ExportError.verificationFailed(expectedTrackID, reason: "missing or mismatched trackID/albumID")
        }
    }
}

private extension ExportMetadataProcessor {
    static func performEmbedExportMetadata(
        _ info: ExportInfo,
        into fileURL: URL,
        timeout: TimeInterval,
        preservingExistingTags: Bool,
    ) async throws {
        AppLog.verbose(logger, "start trackID=\(info.trackID) file=\(fileURL.lastPathComponent)")
        if preservingExistingTags {
            guard EmbeddedTrackIdentity.isTrackID(info.trackID),
                  let albumID = info.albumID, EmbeddedTrackIdentity.isAlbumID(albumID)
            else {
                throw ExportError.verificationFailed(info.trackID, reason: "invalid identity for import fallback")
            }
        }
        guard FileManager.default.isReadableFile(atPath: fileURL.path) else {
            AppLog.warning(logger, "file not readable trackID=\(info.trackID)")
            throw ExportError.fileUnreadable
        }
        let asset = AVURLAsset(url: fileURL)
        guard await (try? asset.load(.isReadable)) == true else {
            AppLog.warning(logger, "asset not readable trackID=\(info.trackID)")
            throw ExportError.fileUnreadable
        }
        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetPassthrough,
        ) else {
            AppLog.warning(logger, "export session unavailable trackID=\(info.trackID)")
            throw ExportError.exportSessionUnavailable
        }

        let outputFileType = try DownloadArtworkProcessor.resolveOutputFileType(
            for: fileURL,
            supportedTypes: exportSession.supportedFileTypes,
        )

        AppLog.verbose(logger, "collecting metadata trackID=\(info.trackID)")
        let existingMetadata = try await AVMetadataHelper.collectMetadataItems(from: asset)

        let hasExistingArtwork = await DownloadArtworkProcessor.containsArtwork(existingMetadata)

        let replacesAlbumArtist = info.albumArtistName.nilIfEmpty != nil
        var metadata = existingMetadata.filter {
            !AVMetadataHelper.isComment($0) && (preservingExistingTags || (
                !AVMetadataHelper.isLyrics($0)
                    && !matchesTitle($0) && !matchesArtist($0) && !matchesAlbum($0)
                    && !(replacesAlbumArtist && AVMetadataHelper.albumArtistTag.priority(of: $0) != nil)
            ))
        }

        try await metadata.append(commentMetadataItem(for: info, preserving: existingMetadata))
        if !preservingExistingTags {
            if let lyrics = info.lyrics, !lyrics.isEmpty {
                metadata.append(lyricsMetadataItem(lyrics))
            }
            metadata.append(contentsOf: standardMetadataItems(for: info))
        }

        if await AVMetadataHelper.trackNumber(in: existingMetadata) == nil,
           let trackNumber = info.trackNumber, trackNumber > 0
        {
            metadata.append(positionMetadataItem(.iTunesMetadataTrackNumber, position: trackNumber, byteCount: 8))
        }
        if await AVMetadataHelper.discNumber(in: existingMetadata) == nil,
           let discNumber = info.discNumber, discNumber > 0
        {
            metadata.append(positionMetadataItem(.iTunesMetadataDiscNumber, position: discNumber, byteCount: 6))
        }

        if !hasExistingArtwork, let artworkData = info.artworkData {
            AppLog.info(logger, "embedding artwork trackID=\(info.trackID) size=\(artworkData.count)")
            metadata.append(contentsOf: DownloadArtworkProcessor.artworkMetadataItems(data: artworkData))
        }

        let tempURL = DownloadArtworkProcessor.temporaryOutputURL(for: fileURL)
        if FileManager.default.fileExists(atPath: tempURL.path) {
            do {
                try FileManager.default.removeItem(at: tempURL)
            } catch {
                AppLog.error(logger, "Failed to remove stale temp file path=\(tempURL.path) error=\(error.localizedDescription)")
            }
        }

        exportSession.outputURL = tempURL
        exportSession.outputFileType = outputFileType
        exportSession.metadata = metadata
        exportSession.shouldOptimizeForNetworkUse = false

        AppLog.verbose(logger, "exporting trackID=\(info.trackID) metadataCount=\(metadata.count)")
        do {
            try await DownloadArtworkProcessor.export(exportSession, timeout: timeout)
            if preservingExistingTags {
                try await verifyEmbeddedMetadata(in: tempURL, expectedTrackID: info.trackID, expectedAlbumID: info.albumID)
            }
            try Task.checkCancellation()
            _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: tempURL)
            AppLog.info(logger, "success trackID=\(info.trackID)")
        } catch {
            AppLog.warning(logger, "export failed trackID=\(info.trackID) error=\(error.localizedDescription)")
            if FileManager.default.fileExists(atPath: tempURL.path) {
                do {
                    try FileManager.default.removeItem(at: tempURL)
                } catch {
                    AppLog.error(logger, "Failed to remove temp file path=\(tempURL.path) error=\(error.localizedDescription)")
                }
            }
            throw error
        }
    }

    enum ExportError: LocalizedError {
        case fileUnreadable
        case exportSessionUnavailable
        case invalidTrackID(String)
        case invalidAlbumID(String, String?)
        case missingTitle(String)
        case missingArtist(String)
        case verificationFailed(String, reason: String)

        var errorDescription: String? {
            switch self {
            case .fileUnreadable:
                "File is not readable or metadata cannot be loaded"
            case .exportSessionUnavailable:
                "Unable to create export session"
            case let .invalidTrackID(id):
                "Invalid track ID: \(id)"
            case let .invalidAlbumID(trackID, albumID):
                "Invalid or missing album ID '\(albumID ?? "nil")' for track \(trackID)"
            case let .missingTitle(trackID):
                "Missing title for track \(trackID)"
            case let .missingArtist(trackID):
                "Missing artist for track \(trackID)"
            case let .verificationFailed(trackID, reason):
                "Metadata verification failed for track \(trackID): \(reason)"
            }
        }
    }

    static func commentMetadataItem(
        for info: ExportInfo,
        preserving items: [AVMetadataItem],
    ) async throws -> AVMetadataItem {
        var payload: [String: Any] = [:]
        var originalComments: [String] = []
        for item in items where AVMetadataHelper.isComment(item) {
            guard let comment = try await item.load(.stringValue) else { continue }
            do {
                if let existing = try EmbeddedTrackIdentity.payload(from: comment) {
                    if existing["trackID"] as? String == info.trackID {
                        payload.merge(existing) { current, _ in current }
                    }
                } else if !originalComments.contains(comment) {
                    originalComments.append(comment)
                }
            } catch EmbeddedTrackIdentity.IdentityError.invalidComment {
                AppLog.warning(logger, "Preserving unrecognized identity comment while exporting known trackID=\(info.trackID)")
                if !originalComments.contains(comment) {
                    originalComments.append(comment)
                }
            }
        }
        if !originalComments.isEmpty {
            let preserved = payload["originalComments"] as? [String] ?? []
            payload["originalComments"] = preserved + originalComments.filter { !preserved.contains($0) }
        }
        payload["v"] = 1
        if EmbeddedTrackIdentity.isLocalTrackID(info.trackID) {
            payload["source"] = EmbeddedTrackIdentity.source
        }
        payload["trackID"] = info.trackID
        if let albumID = info.albumID {
            payload["albumID"] = albumID
        }
        if let artworkURL = info.artworkURL {
            payload["artworkURL"] = artworkURL.absoluteString
        }

        let jsonData = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"

        let item = AVMutableMetadataItem()
        item.identifier = .iTunesMetadataUserComment
        item.value = jsonString as NSString
        return item.copy() as! AVMetadataItem
    }

    static func lyricsMetadataItem(_ lyrics: String) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = .iTunesMetadataLyrics
        item.value = lyrics as NSString
        return item.copy() as! AVMetadataItem
    }

    /// `trkn` (8 bytes) and `disk` (6 bytes): two reserved bytes, the
    /// position as a big-endian UInt16, then a total, left 0 because it is
    /// unknown here.
    static func positionMetadataItem(
        _ identifier: AVMetadataIdentifier,
        position: Int,
        byteCount: Int,
    ) -> AVMetadataItem {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let clamped = UInt16(clamping: position)
        bytes[2] = UInt8(clamped >> 8)
        bytes[3] = UInt8(clamped & 0xFF)
        let item = AVMutableMetadataItem()
        item.identifier = identifier
        item.dataType = kCMMetadataBaseDataType_RawData as String
        item.value = Data(bytes) as NSData
        return item.copy() as! AVMetadataItem
    }

    static func matchesTitle(_ item: AVMetadataItem) -> Bool {
        item.identifier == .commonIdentifierTitle || item.identifier == .iTunesMetadataSongName
    }

    static func matchesArtist(_ item: AVMetadataItem) -> Bool {
        item.identifier == .commonIdentifierArtist || item.identifier == .iTunesMetadataArtist
    }

    static func matchesAlbum(_ item: AVMetadataItem) -> Bool {
        item.identifier == .commonIdentifierAlbumName || item.identifier == .iTunesMetadataAlbum
    }

    static func standardMetadataItems(for info: ExportInfo) -> [AVMetadataItem] {
        var items: [AVMetadataItem] = []

        if let title = info.title, !title.isEmpty {
            let common = AVMutableMetadataItem()
            common.identifier = .commonIdentifierTitle
            common.value = title as NSString
            items.append(common.copy() as! AVMetadataItem)

            let iTunes = AVMutableMetadataItem()
            iTunes.identifier = .iTunesMetadataSongName
            iTunes.value = title as NSString
            items.append(iTunes.copy() as! AVMetadataItem)
        }

        if let artist = info.artistName, !artist.isEmpty {
            let common = AVMutableMetadataItem()
            common.identifier = .commonIdentifierArtist
            common.value = artist as NSString
            items.append(common.copy() as! AVMetadataItem)

            let iTunes = AVMutableMetadataItem()
            iTunes.identifier = .iTunesMetadataArtist
            iTunes.value = artist as NSString
            items.append(iTunes.copy() as! AVMetadataItem)
        }

        if let album = info.albumName, !album.isEmpty {
            let common = AVMutableMetadataItem()
            common.identifier = .commonIdentifierAlbumName
            common.value = album as NSString
            items.append(common.copy() as! AVMetadataItem)

            let iTunes = AVMutableMetadataItem()
            iTunes.identifier = .iTunesMetadataAlbum
            iTunes.value = album as NSString
            items.append(iTunes.copy() as! AVMetadataItem)
        }

        if let albumArtist = info.albumArtistName.nilIfEmpty {
            let iTunes = AVMutableMetadataItem()
            iTunes.identifier = .iTunesMetadataAlbumArtist
            iTunes.value = albumArtist as NSString
            items.append(iTunes.copy() as! AVMetadataItem)
        }

        return items
    }
}
