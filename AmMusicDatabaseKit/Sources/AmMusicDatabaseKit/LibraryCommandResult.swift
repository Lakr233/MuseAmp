//
//  LibraryCommandResult.swift
//  AmMusicDatabaseKit
//
//  Created by @Lakr233 on 2026/04/11.
//

import Foundation

public enum LibraryCommandResult: Sendable, Hashable {
    case none
    case rebuild(scanned: Int, upserted: Int, deleted: Int)
    case ingestedTrack(AudioTrackRecord)
    case createdPlaylist(Playlist)
    case duplicatedPlaylist(Playlist)
    case downloadsQueued(count: Int, skipped: Int)
}
