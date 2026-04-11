//
//  MusicLibraryTrackRemovalService.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import AmMusicDatabaseKit
import Foundation

nonisolated struct MusicLibraryTrackRemovalService {
    private let databaseManager: DatabaseManager

    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    func removeTrack(trackID: String) {
        do {
            _ = try databaseManager.sendSynchronously(.removeTrack(trackID: trackID))
        } catch {
            AppLog.error(self, "removeTrack failed trackID=\(trackID) error=\(error)")
        }
    }

    func removeTracks(_ tracks: [AudioTrackRecord]) {
        guard !tracks.isEmpty else {
            return
        }

        AppLog.info(self, "removeTracks count=\(tracks.count)")
        for track in tracks {
            removeTrack(trackID: track.trackID)
        }
    }
}
