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

    public init(albumArtistName: String? = nil, trackNumber: Int? = nil, discNumber: Int? = nil) {
        self.albumArtistName = albumArtistName.nilIfEmpty
        self.trackNumber = trackNumber.flatMap { $0 > 0 ? $0 : nil }
        self.discNumber = discNumber.flatMap { $0 > 0 ? $0 : nil }
    }

    public var isEmpty: Bool {
        albumArtistName == nil && trackNumber == nil && discNumber == nil
    }
}
