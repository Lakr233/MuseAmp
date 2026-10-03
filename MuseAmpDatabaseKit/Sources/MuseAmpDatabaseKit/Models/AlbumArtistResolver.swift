//
//  AlbumArtistResolver.swift
//  MuseAmpDatabaseKit
//
//  Created by @Lakr233 on 2026/10/03.
//

import Foundation

/// Picks the one artist shown for a whole album: in album lists, album
/// headers, and anywhere albums are grouped or sorted by artist.
public enum AlbumArtistResolver {
    /// Shown when an album has no Album Artist tag and its tracks credit
    /// different artists.
    public static var variousArtistsName: String {
        String(localized: "Various Artists", bundle: .module)
    }

    /// The album-level artist, in this order:
    /// 1. the most common non-empty Album Artist across the tracks;
    /// 2. otherwise the track Artist, when every track credits the same one;
    /// 3. otherwise "Various Artists".
    ///
    /// Names are compared without case or surrounding whitespace, and the
    /// first spelling wins. Track artists are never joined into a list.
    /// Returns nil only when no track has any artist at all.
    public static func albumArtistName(
        albumArtistNames: [String?],
        artistNames: [String],
    ) -> String? {
        if let tagged = mostCommonName(in: albumArtistNames.compactMap(\.nilIfEmpty)) {
            return tagged
        }
        let artists = artistNames.compactMap(\.nilIfEmpty)
        guard let first = artists.first else {
            return nil
        }
        let firstKey = comparisonKey(first)
        if artists.allSatisfy({ comparisonKey($0) == firstKey }) {
            return first
        }
        return variousArtistsName
    }

    /// Applies ``albumArtistName(albumArtistNames:artistNames:)`` to an
    /// album's tracks in disc and track order, so the result does not depend
    /// on how the caller sorted them.
    public static func albumArtistName(for tracks: [AudioTrackRecord]) -> String? {
        let ordered = albumOrdered(tracks)
        return albumArtistName(
            albumArtistNames: ordered.map(\.albumArtistName),
            artistNames: ordered.map(\.artistName),
        )
    }

    /// Only the most common Album Artist tag, or nil when no track has one.
    public static func taggedAlbumArtistName(for tracks: [AudioTrackRecord]) -> String? {
        mostCommonName(in: albumOrdered(tracks).compactMap(\.albumArtistName.nilIfEmpty))
    }
}

private extension AlbumArtistResolver {
    static func albumOrdered(_ tracks: [AudioTrackRecord]) -> [AudioTrackRecord] {
        tracks.sorted { lhs, rhs in
            if lhs.discNumber != rhs.discNumber {
                return (lhs.discNumber ?? .max) < (rhs.discNumber ?? .max)
            }
            if lhs.trackNumber != rhs.trackNumber {
                return (lhs.trackNumber ?? .max) < (rhs.trackNumber ?? .max)
            }
            if lhs.title != rhs.title {
                return lhs.title < rhs.title
            }
            return lhs.trackID < rhs.trackID
        }
    }

    /// Ties go to the name that appears first.
    static func mostCommonName(in names: [String]) -> String? {
        var counts: [String: Int] = [:]
        var firstSpelling: [String: String] = [:]
        var order: [String] = []
        for name in names {
            let key = comparisonKey(name)
            if firstSpelling[key] == nil {
                firstSpelling[key] = name
                order.append(key)
            }
            counts[key, default: 0] += 1
        }
        var bestKey: String?
        var bestCount = 0
        for key in order where counts[key, default: 0] > bestCount {
            bestKey = key
            bestCount = counts[key, default: 0]
        }
        return bestKey.flatMap { firstSpelling[$0] }
    }

    static func comparisonKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
