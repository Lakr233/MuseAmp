//
//  DownloadCoordinator.swift
//  MuseAmpDatabaseKit
//
//  Created by @Lakr233 on 2026/04/11.
//

import Foundation

struct DownloadCoordinator {
    let stateStore: StateStore
    let paths: LibraryPaths
    let logger: DatabaseLogger

    func enqueue(_ requests: [DownloadRequest]) throws -> (queued: Int, skipped: Int) {
        var queued = 0
        var skipped = 0

        for request in requests {
            if try stateStore.download(trackID: request.trackID) != nil {
                skipped += 1
                continue
            }

            let job = DownloadJob(
                trackID: request.trackID,
                albumID: request.albumID,
                targetRelativePath: paths.inferredRelativePath(for: request.trackID, albumID: request.albumID),
                sourceURL: request.sourceURL,
                title: request.title,
                artistName: request.artistName,
                albumTitle: request.albumTitle,
                artworkURL: request.artworkURL,
            )
            try stateStore.upsertDownload(job)
            queued += 1
        }

        logger.info("DownloadCoordinator", "enqueue queued=\(queued) skipped=\(skipped)")
        return (queued, skipped)
    }

    func retry(trackID: String) throws {
        guard let existing = try stateStore.download(trackID: trackID) else {
            return
        }
        let updated = DownloadJob(
            jobID: existing.jobID,
            trackID: existing.trackID,
            albumID: existing.albumID,
            targetRelativePath: existing.targetRelativePath,
            sourceURL: existing.sourceURL,
            title: existing.title,
            artistName: existing.artistName,
            albumTitle: existing.albumTitle,
            artworkURL: existing.artworkURL,
            status: .queued,
            progress: 0,
            retryCount: existing.retryCount + 1,
            errorMessage: nil,
            createdAt: existing.createdAt,
            updatedAt: .init(),
        )
        try stateStore.upsertDownload(updated)
    }
}
