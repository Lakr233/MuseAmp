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

    /// A tag matched by whole identifier or whole key name, never by
    /// substring. AVFoundation exposes M4A atoms as `itsk/aART`, `itsk/trkn`
    /// and so on with numeric keys, which a substring search never finds,
    /// while a substring like "track" also matches `TRACKTOTAL`.
    nonisolated struct ExactTag: Sendable {
        /// Format-specific identifiers, most trusted first.
        let identifiers: [AVMetadataIdentifier]
        /// Free-form key names (QuickTime `mdta`, iTunes `----` atoms,
        /// Vorbis comments), compared with the key's last component,
        /// ignoring case.
        let keyNames: Set<String>

        /// Lower values are preferred; nil when the item is not this tag.
        func priority(of item: AVMetadataItem) -> Int? {
            if let identifier = item.identifier,
               let index = identifiers.firstIndex(of: identifier)
            {
                return index
            }
            guard let key = item.key as? String,
                  let lastComponent = key.split(separator: ".").last
            else {
                return nil
            }
            return keyNames.contains(lastComponent.lowercased()) ? identifiers.count : nil
        }

        func matchingItems(in items: [AVMetadataItem]) -> [AVMetadataItem] {
            items
                .compactMap { item in priority(of: item).map { (item, $0) } }
                .sorted { $0.1 < $1.1 }
                .map(\.0)
        }
    }

    /// The M4A `aART` atom, then the ID3 `TPE2` frame that taggers use for
    /// album artist.
    static let albumArtistTag = ExactTag(
        identifiers: [.iTunesMetadataAlbumArtist, .id3MetadataBand],
        keyNames: ["albumartist", "album_artist", "album artist"],
    )

    /// The M4A `trkn` atom, then ID3 `TRCK`. Totals such as `TRACKTOTAL`
    /// never match.
    static let trackNumberTag = ExactTag(
        identifiers: [.iTunesMetadataTrackNumber, .id3MetadataTrackNumber],
        keyNames: ["tracknumber", "track_number", "track"],
    )

    /// The M4A `disk` atom, then ID3 `TPOS`. Totals such as `DISCTOTAL`
    /// never match.
    static let discNumberTag = ExactTag(
        identifiers: [.iTunesMetadataDiscNumber, .id3MetadataPartOfASet],
        keyNames: ["discnumber", "disc_number", "disc", "disknumber", "disk"],
    )

    static func albumArtistName(in items: [AVMetadataItem]) async -> String? {
        for item in albumArtistTag.matchingItems(in: items) {
            let value = try? await item.load(.stringValue)
            if let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }

    static func trackNumber(in items: [AVMetadataItem]) async -> Int? {
        await position(of: trackNumberTag, in: items)
    }

    static func discNumber(in items: [AVMetadataItem]) async -> Int? {
        await position(of: discNumberTag, in: items)
    }

    /// The first positive position among the tag's items. The total that
    /// often comes with it ("3/13", or the second half of an atom) is ignored.
    static func position(of tag: ExactTag, in items: [AVMetadataItem]) async -> Int? {
        for item in tag.matchingItems(in: items) {
            if let value = await positionValue(of: item), value > 0 {
                return value
            }
        }
        return nil
    }
}

private nonisolated extension AVMetadataHelper {
    static func positionValue(of item: AVMetadataItem) async -> Int? {
        let isBinaryAtom = item.identifier == .iTunesMetadataTrackNumber
            || item.identifier == .iTunesMetadataDiscNumber
        if isBinaryAtom,
           let data = try? await item.load(.dataValue),
           let value = binaryPosition(in: data)
        {
            return value
        }
        if let string = try? await item.load(.stringValue),
           let value = textPosition(in: string)
        {
            return value
        }
        if let number = try? await item.load(.numberValue) {
            return number.intValue
        }
        return nil
    }

    /// `trkn` and `disk` hold two reserved bytes, the position as a
    /// big-endian UInt16, then the total.
    static func binaryPosition(in data: Data) -> Int? {
        guard data.count >= 4 else {
            return nil
        }
        let start = data.startIndex
        return Int(data[start + 2]) << 8 | Int(data[start + 3])
    }

    /// "3", "03" and "3/13" all give 3.
    static func textPosition(in string: String) -> Int? {
        guard let head = string.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).first else {
            return nil
        }
        return Int(head.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
