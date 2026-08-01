//
//  DatabaseManager+Writes.swift
//  MuseAmpDatabaseKit
//
//  Created by @Lakr233 on 2026/04/11.
//

import Foundation

extension DatabaseManager {
    @DatabaseActor
    func rebuildIndex(
        pruneInvalidFiles: Bool,
        forceArtwork: Bool = false,
        progressCallback: (@Sendable (Int, Int) -> Void)? = nil,
    ) async throws -> LibraryCommandResult {
        guard let indexStore else {
            return .rebuild(scanned: 0, upserted: 0, deleted: 0, removedInvalidFiles: [])
        }

        eventSubject.send(.indexRebuildStarted)
        let result = try await libraryScanner().rebuildIndexFromDisk(
            pruneInvalidFiles: pruneInvalidFiles,
            forceArtwork: forceArtwork,
            progressCallback: progressCallback,
        )
        try indexStore.setLastRebuild(timestamp: .init(), succeeded: true)
        try indexStore.setSchemaVersions(
            schema: DatabaseFormat.indexSchemaVersion,
            format: DatabaseFormat.indexFormatVersion,
        )
        if !result.removedInvalidFiles.isEmpty {
            eventSubject.send(.invalidFilesRemoved(relativePaths: result.removedInvalidFiles.map(\.relativePath)))
        }
        if !result.transientFailureRelativePaths.isEmpty {
            DBLog.warning(logger, "DatabaseManager", "rebuild skipped \(result.transientFailureRelativePaths.count) file(s) after transient inspect failures; they remain on disk for the next rebuild")
        }
        eventSubject.send(
            .indexRebuildFinished(
                scanned: result.scanned,
                upserted: result.upserted,
                deleted: result.deleted,
            ),
        )
        return .rebuild(
            scanned: result.scanned,
            upserted: result.upserted,
            deleted: result.deleted,
            removedInvalidFiles: result.removedInvalidFiles,
        )
    }

    @DatabaseActor
    func ingestAudioFile(url: URL, metadata: ImportedTrackMetadata) async throws
        -> AudioTrackRecord
    {
        guard let indexStore else {
            throw NSError(
                domain: "DatabaseManager",
                code: 2,
                userInfo: [
                    NSLocalizedDescriptionKey: String(
                        localized: "DatabaseManager write runtime is unavailable",
                        bundle: .module,
                    ),
                ],
            )
        }

        let inputExtension = url.pathExtension.nilIfEmpty ?? "m4a"
        // Inspect before moving: a file that fails validation never enters the
        // library, the source stays intact, and any previously ingested copy at
        // the destination is not destroyed by the move.
        let inspection = try await dependencies.inspectAudioFile(url)
        let moved = try fileManager.moveToLibrary(
            from: url,
            trackID: metadata.trackID,
            albumID: metadata.albumID,
            fileExtension: inputExtension,
        )
        let attributes = try FileManager.default.attributesOfItem(atPath: moved.finalURL.path)
        let fileSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let modifiedAt = attributes[.modificationDate] as? Date ?? .init()

        if let artwork = inspection.embeddedArtwork {
            try? cacheCoordinator.writeArtwork(data: artwork, trackID: metadata.trackID)
            eventSubject.send(.artworkCacheChanged(trackIDs: [metadata.trackID]))
        }
        if let lyrics = metadata.lyrics.nilIfEmpty ?? inspection.metadata.lyrics.nilIfEmpty {
            try? cacheCoordinator.writeLyrics(text: lyrics, trackID: metadata.trackID)
            eventSubject.send(.lyricsCacheChanged(trackIDs: [metadata.trackID]))
        }

        let existing = try indexStore.track(byID: metadata.trackID)
        let record = AudioTrackRecord(
            trackID: metadata.trackID,
            albumID: metadata.albumID,
            fileExtension: inputExtension,
            relativePath: moved.relativePath,
            fileSizeBytes: fileSize,
            fileModifiedAt: modifiedAt,
            durationSeconds: metadata.durationSeconds ?? inspection.metadata.durationSeconds ?? 0,
            title: metadata.title,
            artistName: metadata.artistName,
            albumTitle: metadata.albumTitle,
            albumArtistName: metadata.albumArtistName,
            trackNumber: metadata.trackNumber,
            discNumber: metadata.discNumber,
            genreName: metadata.genreName,
            composerName: metadata.composerName,
            releaseDate: metadata.releaseDate,
            hasEmbeddedLyrics: (metadata.lyrics.nilIfEmpty ?? inspection.metadata.lyrics.nilIfEmpty)
                != nil,
            hasEmbeddedArtwork: inspection.embeddedArtwork != nil,
            sourceKind: metadata.sourceKind,
            createdAt: existing?.createdAt ?? .init(),
            updatedAt: .init(),
        )
        try indexStore.upsertTracks([record])
        try stateStore?.deleteDownload(trackID: metadata.trackID)
        eventSubject.send(
            .tracksChanged(
                inserted: existing == nil ? [metadata.trackID] : [],
                updated: existing == nil ? [] : [metadata.trackID],
                deleted: [],
            ),
        )
        eventSubject.send(.downloadsChanged(trackIDs: [metadata.trackID]))
        eventSubject.send(.metadataChanged(trackIDs: [metadata.trackID]))
        return record
    }

    @DatabaseActor
    func removeTrack(trackID: String) throws {
        try removeTrackSynchronously(trackID: trackID)
    }

    func removeTrackSynchronously(trackID: String) throws {
        guard let indexStore, let track = try indexStore.track(byID: trackID) else {
            return
        }
        try fileManager.removeTrackFile(relativePath: track.relativePath)
        cacheCoordinator.removeTrackCaches(trackID: trackID)
        try indexStore.deleteTrack(trackID: trackID)
        eventSubject.send(.tracksChanged(inserted: [], updated: [], deleted: [trackID]))
        eventSubject.send(.artworkCacheChanged(trackIDs: [trackID]))
        eventSubject.send(.lyricsCacheChanged(trackIDs: [trackID]))
    }

    @DatabaseActor
    func removeAlbum(albumID: String) throws {
        try removeAlbumSynchronously(albumID: albumID)
    }

    func removeAlbumSynchronously(albumID: String) throws {
        guard let indexStore else {
            return
        }
        let tracks = try indexStore.tracks(inAlbumID: albumID)
        try fileManager.removeAlbumDirectory(albumID: albumID)
        for track in tracks {
            cacheCoordinator.removeTrackCaches(trackID: track.trackID)
        }
        try indexStore.deleteAlbum(albumID: albumID)
        eventSubject.send(.tracksChanged(inserted: [], updated: [], deleted: tracks.map(\.trackID)))
    }
}
