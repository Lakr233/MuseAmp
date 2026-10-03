//
//  DatabaseManager+TagBackfill.swift
//  MuseAmpDatabaseKit
//
//  Created by @Lakr233 on 2026/10/03.
//

import Foundation

public extension DatabaseManager {
    /// The tag backfill this build runs: version 1 filled album artists,
    /// version 2 also fills track and disc numbers.
    static let tagBackfillVersion = 2

    /// Fills in album artist, track and disc numbers for tracks indexed
    /// before those tags were read correctly.
    ///
    /// A library refresh skips files whose size and date are unchanged, so
    /// tracks indexed by an older build would keep these columns empty
    /// forever. This pass runs once per backfill version: it re-reads the tags
    /// of tracks missing any of them and writes each one only into a column
    /// that is still empty. Album and track IDs (and with them playlists,
    /// downloads and likes) stay as they are, and values already stored are
    /// never replaced.
    ///
    /// - Parameter readTags: reads the album artist, track and disc number
    ///   tags of one file.
    /// - Returns: the number of tracks that gained at least one value.
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

        let candidates = try indexStore.allTracks().filter { track in
            track.albumArtistName.nilIfEmpty == nil || track.trackNumber == nil || track.discNumber == nil
        }
        logger.info(
            "DatabaseManager",
            "tag backfill started fromVersion=\(completedVersion) toVersion=\(Self.tagBackfillVersion) candidates=\(candidates.count)",
        )

        let batchSize = 200
        var pending: [String: TrackTags] = [:]
        var updatedTrackIDs: [String] = []
        for track in candidates {
            let read = await readTags(paths.absoluteAudioURL(for: track.relativePath))
            let missing = TrackTags(
                albumArtistName: track.albumArtistName.nilIfEmpty == nil ? read.albumArtistName : nil,
                trackNumber: track.trackNumber == nil ? read.trackNumber : nil,
                discNumber: track.discNumber == nil ? read.discNumber : nil,
            )
            guard !missing.isEmpty else {
                continue
            }
            pending[track.trackID] = missing
            if pending.count >= batchSize {
                try indexStore.fillMissingTags(pending)
                updatedTrackIDs.append(contentsOf: pending.keys)
                pending.removeAll()
            }
        }
        try indexStore.fillMissingTags(pending)
        updatedTrackIDs.append(contentsOf: pending.keys)
        try indexStore.setTagBackfillVersion(Self.tagBackfillVersion)

        logger.info(
            "DatabaseManager",
            "tag backfill finished candidates=\(candidates.count) updated=\(updatedTrackIDs.count)",
        )
        if !updatedTrackIDs.isEmpty {
            eventSubject.send(.tracksChanged(inserted: [], updated: updatedTrackIDs, deleted: []))
            eventSubject.send(.metadataChanged(trackIDs: Set(updatedTrackIDs)))
        }
        return updatedTrackIDs.count
    }
}
