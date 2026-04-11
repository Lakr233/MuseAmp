//
//  DatabaseManager+Commands.swift
//  AmMusicDatabaseKit
//
//  Created by @Lakr233 on 2026/04/11.
//

@preconcurrency import Combine
import Foundation

public extension DatabaseManager {
    func sendSynchronouslyIfSupported(_ command: LibraryCommand) throws
        -> LibraryCommandResult?
    {
        try requireInitialized()

        switch command {
        case let .removeTrack(trackID):
            try removeTrackSynchronously(trackID: trackID)
            return LibraryCommandResult.none
        case let .removeAlbum(albumID):
            try removeAlbumSynchronously(albumID: albumID)
            return LibraryCommandResult.none
        case let .upsertDownloadJob(job):
            try stateStore?.upsertDownload(job)
            eventSubject.send(.downloadsChanged(trackIDs: [job.trackID]))
            return LibraryCommandResult.none
        case let .deleteDownloadJobs(trackIDs):
            try stateStore?.deleteDownloads(trackIDs: trackIDs)
            eventSubject.send(.downloadsChanged(trackIDs: Set(trackIDs)))
            return LibraryCommandResult.none
        case let .enqueueDownloads(requests):
            guard let downloadCoordinator else {
                return .downloadsQueued(count: 0, skipped: requests.count)
            }
            let result = try downloadCoordinator.enqueue(requests)
            eventSubject.send(.downloadsChanged(trackIDs: Set(requests.map(\.trackID))))
            return .downloadsQueued(count: result.queued, skipped: result.skipped)
        case .pauseAllDownloads:
            downloadCoordinator?.pauseAll()
            return LibraryCommandResult.none
        case .resumeAllDownloads:
            downloadCoordinator?.resumeAll()
            return LibraryCommandResult.none
        case let .retryDownload(trackID):
            try downloadCoordinator?.retry(trackID: trackID)
            eventSubject.send(.downloadsChanged(trackIDs: [trackID]))
            return LibraryCommandResult.none
        case let .cancelDownload(trackID):
            try downloadCoordinator?.cancel(trackID: trackID)
            eventSubject.send(.downloadsChanged(trackIDs: [trackID]))
            return LibraryCommandResult.none
        case let .createPlaylist(name):
            guard let stateStore else {
                return LibraryCommandResult.none
            }
            let playlist = try stateStore.createPlaylist(name: name)
            eventSubject.send(.playlistsChanged(ids: [playlist.id]))
            return .createdPlaylist(playlist)
        case let .renamePlaylist(id, name):
            try stateStore?.renamePlaylist(id: id, name: name)
            eventSubject.send(.playlistsChanged(ids: [id]))
            return LibraryCommandResult.none
        case let .deletePlaylist(id):
            try stateStore?.deletePlaylist(id: id)
            eventSubject.send(.playlistsChanged(ids: [id]))
            return LibraryCommandResult.none
        case let .addPlaylistEntry(entry, playlistID):
            try stateStore?.addPlaylistEntry(entry, playlistID: playlistID)
            eventSubject.send(.playlistsChanged(ids: [playlistID]))
            return LibraryCommandResult.none
        case let .removePlaylistEntry(index, playlistID):
            try stateStore?.removePlaylistEntry(index: index, playlistID: playlistID)
            eventSubject.send(.playlistsChanged(ids: [playlistID]))
            return LibraryCommandResult.none
        case let .movePlaylistEntry(playlistID, from, to):
            try stateStore?.movePlaylistEntry(playlistID: playlistID, from: from, to: to)
            eventSubject.send(.playlistsChanged(ids: [playlistID]))
            return LibraryCommandResult.none
        case let .updatePlaylistCover(id, imageData):
            try stateStore?.updatePlaylistCover(id: id, imageData: imageData)
            eventSubject.send(.playlistsChanged(ids: [id]))
            return LibraryCommandResult.none
        case let .updateEntryLyrics(lyrics, trackID, playlistID):
            try stateStore?.updateEntryLyrics(lyrics, trackID: trackID, playlistID: playlistID)
            eventSubject.send(.playlistsChanged(ids: [playlistID]))
            return LibraryCommandResult.none
        case let .importLegacyPlaylists(playlists):
            try stateStore?.importLegacyPlaylists(playlists)
            eventSubject.send(.playlistsChanged(ids: Set(playlists.map(\.id))))
            return LibraryCommandResult.none
        case let .clearPlaylistEntries(playlistID):
            try stateStore?.clearPlaylistEntries(playlistID: playlistID)
            eventSubject.send(.playlistsChanged(ids: [playlistID]))
            return LibraryCommandResult.none
        case let .duplicatePlaylist(id):
            guard let duplicated = try stateStore?.duplicatePlaylist(id: id) else {
                return LibraryCommandResult.none
            }
            eventSubject.send(.playlistsChanged(ids: [id, duplicated.id]))
            return .duplicatedPlaylist(duplicated)
        case .rebuildIndex, .pruneInvalidFiles, .ingestAudioFile:
            return nil
        }
    }

    func sendSynchronously(_ command: LibraryCommand) throws -> LibraryCommandResult {
        if let result = try sendSynchronouslyIfSupported(command) {
            return result
        }

        throw NSError(
            domain: "DatabaseManager",
            code: 4,
            userInfo: [
                NSLocalizedDescriptionKey: String(
                    localized: "Library command requires async send",
                    bundle: .module,
                ),
            ],
        )
    }

    @DatabaseActor
    func send(
        _ command: LibraryCommand,
        progressCallback: (@Sendable (Int, Int) -> Void)? = nil,
    ) async throws -> LibraryCommandResult {
        if let result = try sendSynchronouslyIfSupported(command) {
            return result
        }

        switch command {
        case let .rebuildIndex(pruneInvalidFiles, forceArtwork):
            return try await rebuildIndex(
                pruneInvalidFiles: pruneInvalidFiles,
                forceArtwork: forceArtwork,
                progressCallback: progressCallback,
            )
        case .pruneInvalidFiles:
            _ = try await rebuildIndex(pruneInvalidFiles: true)
            return .none
        case let .ingestAudioFile(url, metadata):
            let ingested = try await ingestAudioFile(url: url, metadata: metadata)
            return .ingestedTrack(ingested)
        default:
            throw NSError(
                domain: "DatabaseManager",
                code: 5,
                userInfo: [
                    NSLocalizedDescriptionKey: String(
                        localized: "Unsupported library command",
                        bundle: .module,
                    ),
                ],
            )
        }
    }
}
