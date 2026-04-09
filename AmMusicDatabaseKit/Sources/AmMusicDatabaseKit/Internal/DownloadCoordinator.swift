import Foundation

struct DownloadCoordinator {
    let stateStore: StateStore
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
                targetRelativePath: "\(sanitizePathComponent(request.albumID))/\(sanitizePathComponent(request.trackID)).m4a",
                sourceURL: request.sourceURL,
                title: request.title,
                artistName: request.artistName,
                albumTitle: request.albumTitle,
                artworkURL: request.artworkURL
            )
            try stateStore.upsertDownload(job)
            queued += 1
        }

        DBLog.info(logger, "DownloadCoordinator", "enqueue queued=\(queued) skipped=\(skipped)")
        return (queued, skipped)
    }

    func pauseAll() {
        DBLog.info(logger, "DownloadCoordinator", "pauseAll")
    }

    func resumeAll() {
        DBLog.info(logger, "DownloadCoordinator", "resumeAll")
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
            updatedAt: .init()
        )
        try stateStore.upsertDownload(updated)
    }

    func cancel(trackID: String) throws {
        try stateStore.deleteDownload(trackID: trackID)
    }
}
