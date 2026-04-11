//
//  LibraryCommand.swift
//  AmMusicDatabaseKit
//
//  Created by @Lakr233 on 2026/04/11.
//

import Foundation

public enum LibraryCommand: Sendable {
    case rebuildIndex(pruneInvalidFiles: Bool, forceArtwork: Bool = false)
    case pruneInvalidFiles
    case ingestAudioFile(url: URL, metadata: ImportedTrackMetadata)
    case removeTrack(trackID: String)
    case removeAlbum(albumID: String)
    case upsertDownloadJob(DownloadJob)
    case deleteDownloadJobs(trackIDs: [String])
    case enqueueDownloads([DownloadRequest])
    case pauseAllDownloads
    case resumeAllDownloads
    case retryDownload(trackID: String)
    case cancelDownload(trackID: String)
    case createPlaylist(name: String)
    case renamePlaylist(id: UUID, name: String)
    case deletePlaylist(id: UUID)
    case addPlaylistEntry(PlaylistEntry, playlistID: UUID)
    case removePlaylistEntry(index: Int, playlistID: UUID)
    case movePlaylistEntry(playlistID: UUID, from: Int, to: Int)
    case updatePlaylistCover(id: UUID, imageData: Data?)
    case updateEntryLyrics(lyrics: String, trackID: String, playlistID: UUID)
    case importLegacyPlaylists([Playlist])
    case clearPlaylistEntries(playlistID: UUID)
    case duplicatePlaylist(id: UUID)
}
