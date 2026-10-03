//
//  AudioTrackRecord+AlbumOrder.swift
//  MuseAmpDatabaseKit
//
//  Created by @Lakr233 on 2026/10/03.
//

import Foundation

public extension AudioTrackRecord {
    /// Album order: disc, then track number, then title. Tracks without a
    /// number come after numbered ones; the track ID breaks the last ties so
    /// every list shows the same order.
    static func isInAlbumOrder(_ lhs: AudioTrackRecord, _ rhs: AudioTrackRecord) -> Bool {
        if lhs.discNumber != rhs.discNumber {
            return (lhs.discNumber ?? .max) < (rhs.discNumber ?? .max)
        }
        if lhs.trackNumber != rhs.trackNumber {
            return (lhs.trackNumber ?? .max) < (rhs.trackNumber ?? .max)
        }
        let titleOrder = lhs.title.localizedStandardCompare(rhs.title)
        if titleOrder != .orderedSame {
            return titleOrder == .orderedAscending
        }
        return lhs.trackID < rhs.trackID
    }
}

public extension Sequence<AudioTrackRecord> {
    func sortedInAlbumOrder() -> [AudioTrackRecord] {
        sorted(by: AudioTrackRecord.isInAlbumOrder)
    }
}
