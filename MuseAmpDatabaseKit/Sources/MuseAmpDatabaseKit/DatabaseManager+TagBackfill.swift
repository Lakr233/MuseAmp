//
//  DatabaseManager+TagBackfill.swift
//  MuseAmpDatabaseKit
//
//  Created by @Lakr233 on 2026/10/03.
//

import Foundation

/// A track or disc number to replace because an older build stored the
/// file's TRACKTOTAL / DISCTOTAL value instead of its position.
struct TrackNumberRepair {
    struct Change {
        let stale: Int
        let position: Int
    }

    var track: Change?
    var disc: Change?

    var isEmpty: Bool {
        track == nil && disc == nil
    }

    /// A stored number is replaced only when it equals the file's total, the
    /// file has a real position, and that position differs. Every other
    /// stored value stays.
    static func change(stored: Int?, position: Int?, total: Int?) -> Change? {
        guard let stored, let position, let total, stored == total, position != stored else {
            return nil
        }
        return Change(stale: stored, position: position)
    }
}

public extension DatabaseManager {
    /// The tag backfill this build runs: version 1 filled album artists,
    /// version 2 also track and disc numbers, version 3 also repairs numbers
    /// older builds read from TRACKTOTAL / DISCTOTAL tags.
    static let tagBackfillVersion = 3

    /// Fills in album artist, track and disc numbers for tracks indexed
    /// before those tags were read correctly, and repairs track and disc
    /// numbers that hold the file's total count.
    ///
    /// A library refresh skips files whose size and date are unchanged, so
    /// tracks indexed by an older build would keep these values forever. This
    /// pass runs once per backfill version and re-reads every track's tags.
    /// It writes a value into a column only while that column is still empty,
    /// and replaces a stored number only when it equals the file's TRACKTOTAL
    /// (or DISCTOTAL) and the file has a different real position. Album and
    /// track IDs (and with them playlists, downloads and likes) stay as they
    /// are; any other stored value is never replaced.
    ///
    /// - Parameter readTags: reads the album artist, track and disc number
    ///   tags, and the free-form totals, of one file.
    /// - Returns: the number of tracks that gained or corrected a value.
    @DatabaseActor
    @discardableResult
    func backfillTrackTagsIfNeeded(
        readTags: @Sendable (URL) async -> TrackTags,
    ) async throws -> Int {
        let indexStore = try requireIndexStore()
        let completedVersion = try indexStore.tagBackfillVersion()
        guard completedVersion < Self.tagBackfillVersion else {
            return 0
        }

        let candidates = try indexStore.allTracks()
        logger.info(
            "DatabaseManager",
            "tag backfill started fromVersion=\(completedVersion) toVersion=\(Self.tagBackfillVersion) candidates=\(candidates.count)",
        )

        let batchSize = 200
        var pendingFills: [String: TrackTags] = [:]
        var pendingRepairs: [String: TrackNumberRepair] = [:]
        var updatedTrackIDs = Set<String>()

        func flush() throws {
            try indexStore.fillMissingTags(pendingFills)
            try indexStore.repairNumbers(pendingRepairs)
            updatedTrackIDs.formUnion(pendingFills.keys)
            updatedTrackIDs.formUnion(pendingRepairs.keys)
            pendingFills.removeAll()
            pendingRepairs.removeAll()
        }

        for track in candidates {
            let read = await readTags(paths.absoluteAudioURL(for: track.relativePath))
            let missing = TrackTags(
                albumArtistName: track.albumArtistName.nilIfEmpty == nil ? read.albumArtistName : nil,
                trackNumber: track.trackNumber == nil ? read.trackNumber : nil,
                discNumber: track.discNumber == nil ? read.discNumber : nil,
            )
            if !missing.isEmpty {
                pendingFills[track.trackID] = missing
            }
            let repair = TrackNumberRepair(
                track: TrackNumberRepair.change(stored: track.trackNumber, position: read.trackNumber, total: read.trackTotal),
                disc: TrackNumberRepair.change(stored: track.discNumber, position: read.discNumber, total: read.discTotal),
            )
            if !repair.isEmpty {
                pendingRepairs[track.trackID] = repair
            }
            if pendingFills.count + pendingRepairs.count >= batchSize {
                try flush()
            }
        }
        try flush()
        try indexStore.setTagBackfillVersion(Self.tagBackfillVersion)

        logger.info(
            "DatabaseManager",
            "tag backfill finished candidates=\(candidates.count) updated=\(updatedTrackIDs.count)",
        )
        if !updatedTrackIDs.isEmpty {
            let trackIDs = updatedTrackIDs.sorted()
            eventSubject.send(.tracksChanged(inserted: [], updated: trackIDs, deleted: []))
            eventSubject.send(.metadataChanged(trackIDs: updatedTrackIDs))
        }
        return updatedTrackIDs.count
    }
}
