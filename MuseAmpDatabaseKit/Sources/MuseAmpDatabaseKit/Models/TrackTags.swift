//
//  TrackTags.swift
//  MuseAmpDatabaseKit
//
//  Created by @Lakr233 on 2026/10/03.
//

import Foundation

/// Album-level tags of one track, as read from its file or reported by the
/// server. A nil field means the source has no value for it.
public struct TrackTags: Sendable, Hashable {
    public let albumArtistName: String?
    public let trackNumber: Int?
    public let discNumber: Int?
    /// The file's free-form TRACKTOTAL / DISCTOTAL values. Older builds read
    /// these as the track or disc number; the backfill uses them only to
    /// recognize and repair such values.
    public let trackTotal: Int?
    public let discTotal: Int?

    public init(
        albumArtistName: String? = nil,
        trackNumber: Int? = nil,
        discNumber: Int? = nil,
        trackTotal: Int? = nil,
        discTotal: Int? = nil,
    ) {
        self.albumArtistName = albumArtistName.nilIfEmpty
        self.trackNumber = Self.positive(trackNumber)
        self.discNumber = Self.positive(discNumber)
        self.trackTotal = Self.positive(trackTotal)
        self.discTotal = Self.positive(discTotal)
    }

    public var isEmpty: Bool {
        albumArtistName == nil && trackNumber == nil && discNumber == nil
            && trackTotal == nil && discTotal == nil
    }

    private static func positive(_ value: Int?) -> Int? {
        value.flatMap { $0 > 0 ? $0 : nil }
    }
}
