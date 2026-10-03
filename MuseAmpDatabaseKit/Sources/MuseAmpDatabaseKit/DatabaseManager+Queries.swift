//
//  DatabaseManager+Queries.swift
//  MuseAmpDatabaseKit
//
//  Created by @Lakr233 on 2026/04/11.
//

import Foundation

public extension DatabaseManager {
    func searchTracks(query: String, limit: Int = 50) throws -> [AudioTrackRecord] {
        try requireIndexStore().searchTracks(query: query, limit: limit)
    }

    func allTracks() throws -> [AudioTrackRecord] {
        try requireIndexStore().allTracks()
    }

    func track(trackID: String) throws -> AudioTrackRecord? {
        try requireIndexStore().track(byID: trackID)
    }

    func allTrackRelativePaths() throws -> [String: String] {
        try requireIndexStore().allTrackRelativePaths()
    }

    func listAlbums() throws -> [AlbumGroup] {
        try requireIndexStore().listAlbums(artworkFileExists: cacheCoordinator.hasArtwork)
    }

    func tracks(inAlbumID albumID: String) throws -> [AudioTrackRecord] {
        try requireIndexStore().tracks(inAlbumID: albumID)
    }

    func recentTracks(limit: Int = 50) throws -> [AudioTrackRecord] {
        try requireIndexStore().recentTracks(limit: limit)
    }

    func activeDownloads() throws -> [DownloadJob] {
        try requireStateStore().activeDownloads()
    }

    func allDownloads() throws -> [DownloadJob] {
        try requireStateStore().allDownloads()
    }

    func failedDownloads() throws -> [DownloadJob] {
        try requireStateStore().failedDownloads()
    }

    func fetchPlaylists() throws -> [Playlist] {
        try requireStateStore().fetchPlaylists()
    }

    func fetchPlaylist(id: UUID) throws -> Playlist? {
        try requireStateStore().fetchPlaylist(id: id)
    }

    func librarySummary() throws -> LibrarySummary {
        try requireIndexStore().librarySummary()
    }
}
