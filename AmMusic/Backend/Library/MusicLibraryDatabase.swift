//
//  MusicLibraryDatabase.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import AmMusicDatabaseKit
import Foundation

nonisolated struct MusicLibrarySummary {
    let trackCount: Int
    let totalBytes: Int64
}

final nonisolated class MusicLibraryDatabase: @unchecked Sendable {
    let paths: LibraryPaths
    let databaseManager: DatabaseManager

    init(databaseManager: DatabaseManager, paths: LibraryPaths) {
        self.databaseManager = databaseManager
        self.paths = paths
    }
}
