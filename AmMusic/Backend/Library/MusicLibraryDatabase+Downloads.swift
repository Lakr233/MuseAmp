import AmMusicDatabaseKit
import Foundation

nonisolated extension MusicLibraryDatabase {
    func allDownloadJobs() throws -> [DownloadJob] {
        try databaseManager.allDownloads()
    }

    func activeDownloadJobs() throws -> [DownloadJob] {
        try databaseManager.activeDownloads()
    }

    func failedDownloadJobs() throws -> [DownloadJob] {
        try databaseManager.failedDownloads()
    }

    func upsertDownloadJob(_ job: DownloadJob) throws {
        _ = try databaseManager.sendSynchronously(.upsertDownloadJob(job))
    }

    func downloadJob(id: String) throws -> DownloadJob? {
        try databaseManager.allDownloads().first(where: { $0.jobID == id })
    }

    func downloadJob(trackID: String) throws -> DownloadJob? {
        try databaseManager.allDownloads().first(where: { $0.trackID == trackID })
    }

    func deleteDownloadRecords(trackIDs: [String]) throws {
        guard !trackIDs.isEmpty else {
            return
        }
        _ = try databaseManager.sendSynchronously(.deleteDownloadJobs(trackIDs: trackIDs))
    }

    func hasDownloadRecord(trackID: String) throws -> Bool {
        if let job = try downloadJob(trackID: trackID) {
            return job.status != .failed
        }
        return false
    }
}
