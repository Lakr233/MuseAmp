//
//  ExportMetadataProcessor.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

@preconcurrency import AVFoundation
import Foundation

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

    private static let logger = "ExportMetadataProcessor"

    static func embedExportMetadata(
        _ info: ExportInfo,
        into fileURL: URL,
        timeout: TimeInterval = 30,
    ) async throws {
        try await DownloadArtworkProcessor.withOverallTimeout(seconds: timeout) {
            try await performEmbedExportMetadata(
                info,
                into: fileURL,
                timeout: timeout,
            )
        }
    }

    /// Validates that the ExportInfo has all required fields for a complete
    /// metadata embed (trackID, albumID, title, artistName must be present).
    static func validateExportInfo(_ info: ExportInfo) throws {
        guard info.trackID.isCatalogID else {
            AppLog.error(logger, "validateExportInfo invalid trackID='\(info.trackID)'")
            throw ExportError.invalidTrackID(info.trackID)
        }
        guard let albumID = info.albumID, albumID.isCatalogID else {
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

    /// Reads back the file metadata and verifies the embedded comment JSON
    /// contains valid trackID and albumID catalog IDs.
    static func verifyEmbeddedMetadata(in fileURL: URL, expectedTrackID: String) async throws {
        AppLog.verbose(logger, "verifyEmbeddedMetadata start trackID=\(expectedTrackID) file=\(fileURL.lastPathComponent)")
        let asset = AVURLAsset(url: fileURL)
        guard await (try? asset.load(.isReadable)) == true else {
            AppLog.error(logger, "verifyEmbeddedMetadata asset not readable trackID=\(expectedTrackID)")
            throw ExportError.verificationFailed(expectedTrackID, reason: "file not readable after export")
        }
        let items = try await AVMetadataHelper.collectMetadataItems(from: asset)
        AppLog.verbose(logger, "verifyEmbeddedMetadata loaded \(items.count) metadata item(s) trackID=\(expectedTrackID)")

        for item in items {
            guard matchesComment(item) else { continue }
            guard let value = try? await item.load(.stringValue),
                  let data = value.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                continue
            }
            guard let trackID = json["trackID"] as? String, trackID.isCatalogID,
                  let albumID = json["albumID"] as? String, albumID.isCatalogID
            else {
                let raw = sanitizedLogText(value, maxLength: 120)
                AppLog.error(logger, "verifyEmbeddedMetadata comment JSON missing valid IDs trackID=\(expectedTrackID) raw='\(raw)'")
                throw ExportError.verificationFailed(expectedTrackID, reason: "comment JSON missing valid trackID/albumID")
            }
            AppLog.verbose(logger, "verifyEmbeddedMetadata passed trackID=\(trackID) albumID=\(albumID)")
            return
        }
        AppLog.error(logger, "verifyEmbeddedMetadata no comment metadata found trackID=\(expectedTrackID)")
        throw ExportError.verificationFailed(expectedTrackID, reason: "no comment metadata item found in exported file")
    }
}

private extension ExportMetadataProcessor {
    static func performEmbedExportMetadata(
        _ info: ExportInfo,
        into fileURL: URL,
        timeout: TimeInterval,
    ) async throws {
        AppLog.verbose(logger, "start trackID=\(info.trackID) file=\(fileURL.lastPathComponent)")
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
        let existingMetadata = try await DownloadArtworkProcessor.collectMetadataItems(from: asset)

        let hasExistingArtwork = await existingMetadataContainsArtwork(existingMetadata)

        var metadata = existingMetadata.filter {
            !matchesComment($0) && !matchesLyrics($0) && !matchesTitle($0) && !matchesArtist($0) && !matchesAlbum($0)
        }

        metadata.append(commentMetadataItem(for: info))
        if let lyrics = info.lyrics, !lyrics.isEmpty {
            metadata.append(lyricsMetadataItem(lyrics))
        }
        metadata.append(contentsOf: standardMetadataItems(for: info))

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

    static func existingMetadataContainsArtwork(_ items: [AVMetadataItem]) async -> Bool {
        for item in items {
            guard DownloadArtworkProcessor.matchesArtwork(item) else { continue }
            let hasData = await (try? item.load(.dataValue)) != nil
            let hasValue = await (try? item.load(.value)) != nil
            if hasData || hasValue {
                return true
            }
        }
        return false
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

    static func commentMetadataItem(for info: ExportInfo) -> AVMetadataItem {
        var payload: [String: Any] = [
            "v": 1,
            "trackID": info.trackID,
        ]
        if let albumID = info.albumID {
            payload["albumID"] = albumID
        }
        if let artworkURL = info.artworkURL {
            payload["artworkURL"] = artworkURL.absoluteString
        }

        let jsonData = (try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])) ?? Data()
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

    static func matchesComment(_ item: AVMetadataItem) -> Bool {
        item.identifier == .iTunesMetadataUserComment
            || AVMetadataHelper.matches(item, tokens: ["comment", "cmt"])
    }

    static func matchesLyrics(_ item: AVMetadataItem) -> Bool {
        item.identifier == .iTunesMetadataLyrics
            || AVMetadataHelper.matches(item, tokens: ["lyrics", "lyr"])
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

        return items
    }
}
