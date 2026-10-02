//
//  DatabaseManager+Audit.swift
//  MuseAmpDatabaseKit
//
//  Created by @Lakr233 on 2026/04/11.
//

import Foundation

public extension DatabaseManager {
    func auditSnapshot() async throws -> AuditSnapshot {
        let indexStore = try requireIndexStore()
        let stateStore = try requireStateStore()

        let validTrackIDs = try indexStore.trackIDs()
        let artworkCount = cacheCoordinator.countFiles(in: paths.artworkCacheDirectory)
        let lyricsCount = cacheCoordinator.countFiles(in: paths.lyricsCacheDirectory)
        let orphanArtwork = try cacheCoordinator.orphanArtworkTrackIDs(validTrackIDs: validTrackIDs)
            .count
        let orphanLyrics = try cacheCoordinator.orphanLyricsTrackIDs(validTrackIDs: validTrackIDs).count
        let unresolvedPlaylistEntries = try stateStore.unresolvedPlaylistEntryCount(
            validTrackIDs: validTrackIDs,
        )
        let indexSchemaVersion = try indexStore.schemaVersion()
        let indexFormatVersion = try indexStore.formatVersion()
        let stateSchemaVersion = try stateStore.schemaVersion()
        let scanner = try libraryScanner()
        let invalidPathsFound = scanner.discoverAudioFiles().count(where: { url in
            !scanner.validatePath(paths.relativeAudioPath(for: url))
        })
        let issues = buildAuditIssues(
            orphanArtwork: orphanArtwork,
            orphanLyrics: orphanLyrics,
            invalidPathsFound: invalidPathsFound,
            unresolvedPlaylistEntries: unresolvedPlaylistEntries,
        )

        eventSubject.send(.auditUpdated)
        return try AuditSnapshot(
            indexDatabase: .init(
                path: paths.indexDatabaseURL.path,
                sizeBytes: fileSize(at: paths.indexDatabaseURL),
                schemaVersion: indexSchemaVersion,
                formatVersion: indexFormatVersion,
            ),
            stateDatabase: .init(
                path: paths.stateDatabaseURL.path,
                sizeBytes: fileSize(at: paths.stateDatabaseURL),
                schemaVersion: stateSchemaVersion,
                formatVersion: nil,
            ),
            counts: .init(
                tracks: indexStore.allTracks().count,
                albums: indexStore.listAlbums(artworkFileExists: cacheCoordinator.hasArtwork).count,
                playlists: stateStore.playlistCount(),
                playlistEntries: stateStore.playlistEntryCount(),
                activeDownloads: stateStore.activeDownloads().count,
                failedDownloads: stateStore.failedDownloads().count,
                artworkFiles: artworkCount,
                lyricsFiles: lyricsCount,
            ),
            invalidPathsFound: invalidPathsFound,
            orphanArtworkFiles: orphanArtwork,
            orphanLyricsFiles: orphanLyrics,
            stagedTempFiles: tempFileCount(),
            unresolvedPlaylistEntries: unresolvedPlaylistEntries,
            stateIndexVersionMismatch: indexSchemaVersion != DatabaseFormat.indexSchemaVersion
                || stateSchemaVersion != DatabaseFormat.stateSchemaVersion,
            currentIndexSchemaVersion: DatabaseFormat.indexSchemaVersion,
            currentIndexFormatVersion: DatabaseFormat.indexFormatVersion,
            currentStateSchemaVersion: DatabaseFormat.stateSchemaVersion,
            lastRebuildSucceeded: indexStore.lastRebuildSucceeded(),
            lastRebuildTimestamp: indexStore.lastRebuildTimestamp(),
            issues: issues,
        )
    }
}
