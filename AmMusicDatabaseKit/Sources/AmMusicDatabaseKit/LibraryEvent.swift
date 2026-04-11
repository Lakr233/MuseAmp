//
//  LibraryEvent.swift
//  AmMusicDatabaseKit
//
//  Created by @Lakr233 on 2026/04/11.
//

import Foundation

public enum LibraryEvent: Sendable, Hashable {
    case runtimeReady
    case indexResetStarted(reason: DatabaseResetReason)
    case indexResetFinished(reason: DatabaseResetReason)
    case indexRebuildStarted
    case indexRebuildFinished(scanned: Int, upserted: Int, deleted: Int)
    case invalidFilesRemoved(relativePaths: [String])
    case tracksChanged(inserted: [String], updated: [String], deleted: [String])
    case downloadsChanged(trackIDs: Set<String>)
    case playlistsChanged(ids: Set<UUID>)
    case artworkCacheChanged(trackIDs: Set<String>)
    case lyricsCacheChanged(trackIDs: Set<String>)
    case metadataChanged(trackIDs: Set<String>)
    case auditUpdated
}
