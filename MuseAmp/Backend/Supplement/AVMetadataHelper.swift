//
//  AVMetadataHelper.swift
//  MuseAmp
//
//  Created by @Lakr233 on 2026/04/11.
//

@preconcurrency import AVFoundation
import Foundation

nonisolated enum AVMetadataHelper {
    static func collectMetadataItems(from asset: AVURLAsset) async throws -> [AVMetadataItem] {
        var items = try await asset.load(.commonMetadata)
        let formats = try await asset.load(.availableMetadataFormats)
        for format in formats {
            try await items.append(contentsOf: asset.loadMetadata(for: format))
        }
        return items
    }

    static func matches(_ item: AVMetadataItem, tokens: [String]) -> Bool {
        let identifier = item.identifier?.rawValue.lowercased() ?? ""
        let commonKey = item.commonKey?.rawValue.lowercased() ?? ""
        let key = (item.key as? String)?.lowercased() ?? (item.key as? NSString)?.lowercased ?? ""
        return tokens.contains { token in
            identifier.contains(token) || commonKey.contains(token) || key.contains(token)
        }
    }

    static func isComment(_ item: AVMetadataItem) -> Bool {
        item.identifier == .iTunesMetadataUserComment
            || AVMetadataHelper.matches(item, tokens: ["comment", "cmt"])
    }

    static func isLyrics(_ item: AVMetadataItem) -> Bool {
        item.identifier == .iTunesMetadataLyrics
            || AVMetadataHelper.matches(item, tokens: ["lyrics", "lyr"])
    }

    /// Album Artist tags in the order they are trusted: the M4A `aART` atom,
    /// then the ID3 `TPE2` frame that taggers use for album artist.
    static let albumArtistIdentifiers: [AVMetadataIdentifier] = [
        .iTunesMetadataAlbumArtist,
        .id3MetadataBand,
    ]

    /// Free-form keys (QuickTime `mdta`, iTunes `----` atoms, Vorbis
    /// comments) whose last component names the album artist exactly.
    static let albumArtistKeyNames: Set<String> = ["albumartist", "album_artist", "album artist"]

    /// Matches whole identifiers and keys only. AVFoundation exposes the M4A
    /// tag as `itsk/aART` with a numeric key, so a substring search for
    /// "albumArtist" never finds it. Lower values are preferred.
    static func albumArtistPriority(of item: AVMetadataItem) -> Int? {
        if let identifier = item.identifier,
           let index = albumArtistIdentifiers.firstIndex(of: identifier)
        {
            return index
        }
        guard let key = item.key as? String,
              let lastComponent = key.split(separator: ".").last
        else {
            return nil
        }
        return albumArtistKeyNames.contains(lastComponent.lowercased()) ? albumArtistIdentifiers.count : nil
    }

    static func albumArtistName(in items: [AVMetadataItem]) async -> String? {
        let candidates = items
            .compactMap { item in albumArtistPriority(of: item).map { (item, $0) } }
            .sorted { $0.1 < $1.1 }
        for (item, _) in candidates {
            let value = try? await item.load(.stringValue)
            if let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }
}
