//
//  DatabaseManager+Queries.swift
//  MuseAmpDatabaseKit
//
//  Created by @Lakr233 on 2026/04/11.
//

import Foundation

public extension DatabaseManager {
    func searchTracks(query: String, limit: Int = 50) throws -> [AudioTrackRecord] {
        try requireInitialized()
        guard let indexStore else {
            return []
        }
        return try indexStore.searchTracks(query: query, limit: limit)
    }

    func allTracks() throws -> [AudioTrackRecord] {
        try requireInitialized()
        guard let indexStore else {
            return []
        }
        return try indexStore.allTracks()
    }

    func track(trackID: String) throws -> AudioTrackRecord? {
        try requireInitialized()
        return try indexStore?.track(byID: trackID)
    }

    func allTrackRelativePaths() throws -> [String: String] {
        try requireInitialized()
        guard let indexStore else {
            return [:]
        }
        return try indexStore.allTrackRelativePaths()
    }

    func listAlbums() throws -> [AlbumGroup] {
        try requireInitialized()
        guard let indexStore else {
            return []
        }
        return try indexStore.listAlbums(artworkFileExists: cacheCoordinator.hasArtwork)
    }

    func tracks(inAlbumID albumID: String) throws -> [AudioTrackRecord] {
        try requireInitialized()
        guard let indexStore else {
            return []
        }
        return try indexStore.tracks(inAlbumID: albumID)
    }

    func recentTracks(limit: Int = 50) throws -> [AudioTrackRecord] {
        try requireInitialized()
        guard let indexStore else {
            return []
        }
        return try indexStore.recentTracks(limit: limit)
    }

    func activeDownloads() throws -> [DownloadJob] {
        try requireInitialized()
        return try stateStore?.activeDownloads() ?? []
    }

    func allDownloads() throws -> [DownloadJob] {
        try requireInitialized()
        return try stateStore?.allDownloads() ?? []
    }

    func failedDownloads() throws -> [DownloadJob] {
        try requireInitialized()
        return try stateStore?.failedDownloads() ?? []
    }

    func fetchPlaylists() throws -> [Playlist] {
        try requireInitialized()
        return try stateStore?.fetchPlaylists() ?? []
    }

    func fetchPlaylist(id: UUID) throws -> Playlist? {
        try requireInitialized()
        return try stateStore?.fetchPlaylist(id: id)
    }

    func librarySummary() throws -> LibrarySummary {
        try requireInitialized()
        guard let indexStore else {
            return LibrarySummary(
                trackCount: 0, albumCount: 0, totalSizeBytes: 0, totalDurationSeconds: 0,
            )
        }
        return try indexStore.librarySummary()
    }
}
