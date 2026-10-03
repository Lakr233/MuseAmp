//
//  DatabaseManager+AlbumArtistBackfill.swift
//  MuseAmpDatabaseKit
//
//  Created by @Lakr233 on 2026/10/03.
//

import Foundation

public extension DatabaseManager {
    /// Fills in Album Artist for tracks indexed before the tag was read.
    ///
    /// A library refresh skips files whose size and date are unchanged, so
    /// tracks indexed by an older build would keep a missing album artist
    /// forever. This pass runs once per index: it re-reads only the album
    /// artist of tracks that have none and writes only that column, so album
    /// and track IDs (and with them playlists, downloads and likes) stay as
    /// they are. Tracks without the tag keep none.
    ///
    /// - Parameter readAlbumArtist: reads the Album Artist tag of one file.
    /// - Returns: the number of tracks that gained an album artist.
    @DatabaseActor
    @discardableResult
    func backfillAlbumArtistsIfNeeded(
        readAlbumArtist: @Sendable (URL) async -> String?,
    ) async throws -> Int {
        let indexStore = try requireIndexStore()
        guard try !indexStore.albumArtistBackfillCompleted() else {
            return 0
        }

        let candidates = try indexStore.allTracks().filter { $0.albumArtistName.nilIfEmpty == nil }
        logger.info("DatabaseManager", "album artist backfill started candidates=\(candidates.count)")

        let batchSize = 200
        var pending: [String: String] = [:]
        var updatedTrackIDs: [String] = []
        for track in candidates {
            let fileURL = paths.absoluteAudioURL(for: track.relativePath)
            guard let name = await readAlbumArtist(fileURL).nilIfEmpty else {
                continue
            }
            pending[track.trackID] = name
            if pending.count >= batchSize {
                try indexStore.fillMissingAlbumArtistNames(pending)
                updatedTrackIDs.append(contentsOf: pending.keys)
                pending.removeAll()
            }
        }
        try indexStore.fillMissingAlbumArtistNames(pending)
        updatedTrackIDs.append(contentsOf: pending.keys)
        try indexStore.markAlbumArtistBackfillCompleted()

        logger.info(
            "DatabaseManager",
            "album artist backfill finished candidates=\(candidates.count) updated=\(updatedTrackIDs.count)",
        )
        if !updatedTrackIDs.isEmpty {
            eventSubject.send(.tracksChanged(inserted: [], updated: updatedTrackIDs, deleted: []))
            eventSubject.send(.metadataChanged(trackIDs: Set(updatedTrackIDs)))
        }
        return updatedTrackIDs.count
    }
}
