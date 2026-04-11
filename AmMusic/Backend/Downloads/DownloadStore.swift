//
//  DownloadStore.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import AmMusicDatabaseKit
import Foundation

final nonisolated class DownloadStore {
    private let database: MusicLibraryDatabase
    private let paths: LibraryPaths

    init(database: MusicLibraryDatabase, paths: LibraryPaths) {
        self.database = database
        self.paths = paths
    }

    // MARK: - Download Jobs (active/in-progress only)

    func allRecords() -> [DownloadJob] {
        do { return try database.allDownloadJobs() }
        catch { AppLog.error(self, "allRecords failed: \(error)"); return [] }
    }

    func activeRecords() -> [DownloadJob] {
        do { return try database.activeDownloadJobs() }
        catch { AppLog.error(self, "activeRecords failed: \(error)"); return [] }
    }

    func failedRecords() -> [DownloadJob] {
        do { return try database.failedDownloadJobs() }
        catch { AppLog.error(self, "failedRecords failed: \(error)"); return [] }
    }

    func activeCount() -> Int {
        activeRecords().count
    }

    func hasRecord(trackID: String) -> Bool {
        do { return try database.hasDownloadRecord(trackID: trackID) }
        catch { AppLog.error(self, "hasRecord failed trackID=\(trackID): \(error)"); return false }
    }

    func record(id: String) -> DownloadJob? {
        do { return try database.downloadJob(id: id) }
        catch { AppLog.error(self, "record(id:) failed id=\(id): \(error)"); return nil }
    }

    func record(trackID: String) -> DownloadJob? {
        do { return try database.downloadJob(trackID: trackID) }
        catch { AppLog.error(self, "record(trackID:) failed trackID=\(trackID): \(error)"); return nil }
    }

    func upsert(_ job: DownloadJob) {
        do { try database.upsertDownloadJob(job) }
        catch { AppLog.error(self, "upsert failed id=\(job.jobID): \(error)") }
    }

    func deleteRecords(trackIDs: [String]) {
        do { try database.deleteDownloadRecords(trackIDs: trackIDs) }
        catch { AppLog.error(self, "deleteRecords failed count=\(trackIDs.count): \(error)") }
    }

    // MARK: - Downloaded Status (from tracks table)

    func isDownloaded(trackID: String) -> Bool {
        guard let track = database.trackOrNil(byID: trackID) else {
            return false
        }
        let fileURL = paths.absoluteAudioURL(for: track.relativePath)
        let exists = FileManager.default.fileExists(atPath: fileURL.path)
        AppLog.verbose(
            self,
            "isDownloaded trackID=\(trackID) trackExists=true fileExists=\(exists) relativePath='\(track.relativePath)'",
        )
        return exists
    }

    func storageSize(forTrackIDs trackIDs: Set<String>, audioDirectory _: URL) -> Int64 {
        do {
            let allTracks = try database.allTracks()
            var total: Int64 = 0
            for track in allTracks where trackIDs.contains(track.trackID) {
                total += track.fileSizeBytes
            }
            return total
        } catch {
            AppLog.error(self, "storageSize failed: \(error)")
            return 0
        }
    }
}
