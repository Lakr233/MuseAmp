import AmMusicDatabaseKit
import Foundation

extension SongLibraryIndexer {
    struct SyncResult {
        let filesScanned: Int
        let upserts: Int
        let deletions: Int
        let purged: Int
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
        progressCallback: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> SyncResult {
        let result = try await databaseManager.send(
            .rebuildIndex(pruneInvalidFiles: true, forceArtwork: forceArtwork),
            progressCallback: progressCallback
        )
        if case let .rebuild(scanned, upserted, deleted) = result {
            AppLog.info(
                self,
                "syncLibrary finished files=\(scanned) upserts=\(upserted) deletions=\(deleted)"
            )
            return SyncResult(
                filesScanned: scanned,
                upserts: upserted,
                deletions: deleted,
                purged: 0
            )
        }

        AppLog.warning(self, "syncLibrary returned unexpected result")
        return SyncResult(filesScanned: 0, upserts: 0, deletions: 0, purged: 0)
    }
}
