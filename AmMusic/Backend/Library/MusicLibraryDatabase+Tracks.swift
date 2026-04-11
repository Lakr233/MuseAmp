//
//  MusicLibraryDatabase+Tracks.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import AmMusicDatabaseKit
import Foundation

nonisolated extension MusicLibraryDatabase {
    func sendCommand(_ command: LibraryCommand) async throws -> LibraryCommandResult {
        if let result = try databaseManager.sendSynchronouslyIfSupported(command) {
            return result
        }

        let databaseManager = databaseManager
        return try await databaseManager.send(command)
    }

    func deleteTracks(relativePaths: [String]) async throws {
        let tracks = try allTracks().filter { relativePaths.contains($0.relativePath) }
        for track in tracks {
            _ = try await sendCommand(.removeTrack(trackID: track.trackID))
        }
    }

    func storedLibrarySummary() throws -> MusicLibrarySummary {
        let summary = try databaseManager.librarySummary()
        return MusicLibrarySummary(
            trackCount: summary.trackCount, totalBytes: summary.totalSizeBytes,
        )
    }

    func allTracks() throws -> [AudioTrackRecord] {
        try databaseManager.allTracks()
    }

    func track(byID trackID: String) throws -> AudioTrackRecord? {
        try databaseManager.track(trackID: trackID)
    }

    func trackOrNil(byID trackID: String) -> AudioTrackRecord? {
        do {
            return try track(byID: trackID)
        } catch {
            AppLog.error(self, "trackOrNil failed trackID=\(trackID): \(error)")
            return nil
        }
    }

    func hasTrack(byID trackID: String) -> Bool {
        do {
            return try track(byID: trackID) != nil
        } catch {
            AppLog.error(self, "hasTrack failed trackID=\(trackID): \(error)")
            return false
        }
    }

    func allTrackRelativePaths() throws -> [String: String] {
        try databaseManager.allTrackRelativePaths()
    }

    func searchTracks(query: String) throws -> [AudioTrackRecord] {
        try databaseManager.searchTracks(query: query)
    }

    func allAlbums() throws -> [AlbumGroup] {
        try databaseManager.listAlbums()
    }

    func removeAllStoredSongs() async throws {
        for track in try allTracks() {
            _ = try await sendCommand(.removeTrack(trackID: track.trackID))
        }
    }
}
