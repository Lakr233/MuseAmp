//
//  SongLibraryIndexer.swift
//  MuseAmp
//
//  Created by @Lakr233 on 2026/04/11.
//

import Foundation
import MuseAmpDatabaseKit

extension SongLibraryIndexer {
    struct SyncResult {
        let filesScanned: Int
        let upserts: Int
        let deletions: Int
        let removedInvalidFiles: [RemovedInvalidFile]
    }
}

final class SongLibraryIndexer: @unchecked Sendable {
    private let databaseManager: DatabaseManager

    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    @discardableResult
    func syncLibrary(
        forceArtwork: Bool = false,
        progressCallback: (@Sendable (Int, Int) -> Void)? = nil,
    ) async throws -> SyncResult {
        let result = try await databaseManager.send(
            .rebuildIndex(pruneInvalidFiles: true, forceArtwork: forceArtwork),
            progressCallback: progressCallback,
        )
        if case let .rebuild(scanned, upserted, deleted, removedInvalidFiles) = result {
            AppLog.info(
                self,
                "syncLibrary finished files=\(scanned) upserts=\(upserted) deletions=\(deleted) invalid=\(removedInvalidFiles.count)",
            )
            return SyncResult(
                filesScanned: scanned,
                upserts: upserted,
                deletions: deleted,
                removedInvalidFiles: removedInvalidFiles,
            )
        }

        AppLog.warning(self, "syncLibrary returned unexpected result")
        return SyncResult(filesScanned: 0, upserts: 0, deletions: 0, removedInvalidFiles: [])
    }
}
