//
//  DownloadManager+Queue.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import AmMusicDatabaseKit
import Digger
import Foundation

// MARK: - Processing Queue

extension DownloadManager {
    var activeCount: Int {
        tasks.values.count(where: { $0.state == .resolving || $0.state == .downloading })
    }

    func processNextIfNeeded() {
        guard !isPausedAll else { return }
        updateDeferredStatesForPendingTasks()
        if activeCount == 0 {
            syncDiggerHTTPHeadersIfNeeded()
        }
        while activeCount < maxConcurrent {
            guard
                let nextKey = tasks.values
                .first(where: { $0.state == .waiting && !shouldDeferForNetwork(trackID: $0.trackID) })?
                .trackID
            else {
                return
            }
            startResolving(trackID: nextKey)
        }
    }

    func startResolving(trackID: String) {
        guard let task = tasks[trackID] else {
            AppLog.warning(self, "startResolving: task not found for trackID=\(trackID)")
            return
        }

        // URL already resolved (e.g. resuming after pause-during-resolve) — skip API call
        if let url = task.url {
            tasks[trackID]?.state = .downloading
            persistRecord(trackID: trackID, state: .downloading, sourceURL: url.absoluteString)
            publishSnapshot()
            if diggerStartedURLs.contains(url) {
                DiggerManager.shared.startTask(for: url)
            } else if let task = tasks[trackID] {
                startDiggerDownload(for: task)
            }
            return
        }

        tasks[trackID]?.state = .resolving
        persistRecord(trackID: trackID, state: .resolving)
        publishSnapshot()

        Task { [weak self] in
            guard let self else { return }
            do {
                let info = try await apiClient.playback(id: trackID)
                guard let url = URL(string: info.playbackURL) else {
                    AppLog.error(self, "Invalid playback URL for trackID=\(trackID): \(info.playbackURL)")
                    failTask(trackID: trackID, error: "Invalid playback URL")
                    return
                }
                tasks[trackID]?.url = url

                if isPausedAll {
                    tasks[trackID]?.state = .paused
                    persistRecord(trackID: trackID, state: .queued, sourceURL: url.absoluteString)
                    publishSnapshot()
                    return
                }

                if shouldDeferForNetwork(trackID: trackID) {
                    tasks[trackID]?.state = .waitingForNetwork
                    persistRecord(trackID: trackID, state: .waitingForNetwork, sourceURL: url.absoluteString)
                    publishSnapshot()
                    return
                }

                tasks[trackID]?.state = .downloading
                persistRecord(trackID: trackID, state: .downloading, sourceURL: url.absoluteString)
                publishSnapshot()
                if let task = tasks[trackID] {
                    startDiggerDownload(for: task)
                }
            } catch {
                AppLog.error(
                    self, "API playback failed for trackID=\(trackID): \(error.localizedDescription)",
                )
                await apiClient.invalidatePlaybackCache(id: trackID)
                failTask(trackID: trackID, error: error.localizedDescription)
            }
        }
    }

    func failTask(trackID: String, error: String) {
        AppLog.error(self, "failTask trackID=\(trackID), error=\(error)")
        tasks[trackID]?.markFailed()
        persistRecord(trackID: trackID, state: .failed, lastError: error)
        publishSnapshot()
        processNextIfNeeded()
    }

    func rehydrateQueuedRecord(_ record: DownloadJob) {
        let trackID = record.trackID
        guard tasks[trackID] == nil else {
            return
        }
        let destPath = record.targetRelativePath.isEmpty
            ? paths.inferredRelativePath(for: trackID, albumID: record.albumID)
            : record.targetRelativePath
        let albumID = (destPath as NSString).deletingLastPathComponent

        if destPath != record.targetRelativePath {
            let updated = DownloadJob(
                jobID: record.jobID,
                trackID: record.trackID,
                albumID: record.albumID,
                targetRelativePath: destPath,
                sourceURL: record.sourceURL,
                title: record.title,
                artistName: record.artistName,
                albumTitle: record.albumTitle,
                artworkURL: record.artworkURL,
                status: record.status,
                progress: record.progress,
                retryCount: record.retryCount,
                errorMessage: record.errorMessage,
                createdAt: record.createdAt,
                updatedAt: Date(),
            )
            downloadStore.upsert(updated)
        }

        let task = ActiveDownloadTask(
            id: record.jobID,
            trackID: trackID,
            albumID: albumID,
            title: record.title,
            artistName: record.artistName,
            albumName: record.albumTitle,
            artworkURL: apiClient.mediaURL(from: record.artworkURL, width: 600, height: 600),
            destinationRelativePath: destPath,
            progress: 0,
            speed: 0,
            retryCount: record.retryCount,
            state: record.status == .waitingForNetwork ? .waitingForNetwork : .waiting,
            queueOrder: allocateQueueOrder(),
        )
        tasks[trackID] = task
    }

    func rehydrateFailedRecord(_ record: DownloadJob) {
        let trackID = record.trackID
        guard tasks[trackID] == nil else { return }
        let destPath = record.targetRelativePath
        let albumID = (destPath as NSString).deletingLastPathComponent

        let task = ActiveDownloadTask(
            id: record.jobID,
            trackID: trackID,
            albumID: albumID,
            title: record.title,
            artistName: record.artistName,
            albumName: record.albumTitle,
            artworkURL: apiClient.mediaURL(from: record.artworkURL, width: 600, height: 600),
            destinationRelativePath: destPath,
            progress: 0,
            speed: 0,
            retryCount: record.retryCount,
            state: .failed,
            queueOrder: allocateQueueOrder(),
        )
        tasks[trackID] = task
    }

    func rehydrateFinalizingRecord(_ record: DownloadJob) {
        let trackID = record.trackID
        guard tasks[trackID] == nil else {
            return
        }
        let destPath = record.targetRelativePath
        let finalURL = paths.absoluteAudioURL(for: destPath)
        let tmpURL = Self.finalizingURL(for: finalURL)
        let fileURL = FileManager.default.fileExists(atPath: tmpURL.path) ? tmpURL : finalURL
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            AppLog.warning(
                self, "rehydrateFinalizingRecord missing file for trackID=\(trackID), requeuing",
            )
            let queuedRecord = DownloadJob(
                jobID: record.jobID,
                trackID: record.trackID,
                albumID: record.albumID,
                targetRelativePath: record.targetRelativePath,
                title: record.title,
                artistName: record.artistName,
                albumTitle: record.albumTitle,
                artworkURL: record.artworkURL,
                status: .queued,
                progress: 0,
                retryCount: record.retryCount,
                errorMessage: record.errorMessage,
                createdAt: record.createdAt,
                updatedAt: Date(),
            )
            downloadStore.upsert(queuedRecord)
            rehydrateQueuedRecord(queuedRecord)
            return
        }

        let albumID = (destPath as NSString).deletingLastPathComponent
        let task = ActiveDownloadTask(
            id: record.jobID,
            trackID: trackID,
            albumID: albumID,
            title: record.title,
            artistName: record.artistName,
            albumName: record.albumTitle,
            artworkURL: apiClient.mediaURL(from: record.artworkURL, width: 600, height: 600),
            destinationRelativePath: destPath,
            progress: 1,
            speed: 0,
            retryCount: record.retryCount,
            state: .finalizing,
            queueOrder: allocateQueueOrder(),
        )
        tasks[trackID] = task
        startFinalizing(trackID: trackID, fileURL: fileURL)
    }
}
