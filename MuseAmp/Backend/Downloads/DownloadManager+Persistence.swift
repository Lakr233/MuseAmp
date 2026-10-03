//
//  DownloadManager+Persistence.swift
//  MuseAmp
//
//  Created by @Lakr233 on 2026/04/11.
//

import Combine
import Foundation
import MuseAmpDatabaseKit

// MARK: - Persistence & Helpers

extension DownloadManager {
    /// Returns the temporary URL used during finalization by prefixing the
    /// filename with `.tmp.`, preserving the original file extension so that
    /// AVFoundation can still identify the audio format.
    static func finalizingURL(for finalURL: URL) -> URL {
        finalURL.deletingLastPathComponent()
            .appendingPathComponent(".tmp." + finalURL.lastPathComponent)
    }

    func persistRecord(
        trackID: String,
        state: DownloadJobStatus,
        progress: Double = 0,
        sourceURL: String? = nil,
        localRelativePath: String? = nil,
        retryCount: Int? = nil,
        lastError: String? = nil,
    ) {
        guard let task = tasks[trackID] else {
            return
        }
        let job = DownloadJob(
            jobID: task.id,
            trackID: task.trackID,
            albumID: task.albumID,
            targetRelativePath: localRelativePath ?? task.destinationRelativePath,
            sourceURL: sourceURL ?? task.url?.absoluteString,
            title: task.title,
            artistName: task.artistName,
            albumTitle: task.albumName,
            artworkURL: task.artworkURL?.absoluteString,
            status: state,
            progress: progress,
            retryCount: retryCount ?? task.retryCount,
            errorMessage: lastError,
            updatedAt: Date(),
        )
        downloadStore.upsert(job)
    }

    func completeFinalization(trackID: String, ingestionError: (any Error)?) async {
        guard let task = tasks[trackID] else {
            AppLog.warning(self, "completeFinalization missing task for trackID=\(trackID)")
            return
        }

        if ingestionError == nil {
            downloadStore.deleteRecords(trackIDs: [trackID])
            AppLog.info(
                self, "Download completed trackID=\(trackID) relativePath=\(task.destinationRelativePath)",
            )
            tasks.removeValue(forKey: trackID)
        } else if let ingestionError {
            AppLog.warning(
                self,
                "Library ingest failed after finalizing trackID=\(trackID): \(ingestionError.localizedDescription)",
            )
            tasks[trackID]?.markFailed(error: ingestionError.localizedDescription)
            tasks[trackID]?.progress = 1
            persistRecord(
                trackID: trackID,
                state: .failed,
                progress: 1,
                localRelativePath: task.destinationRelativePath,
                retryCount: task.retryCount,
                lastError: ingestionError.localizedDescription,
            )
        }

        publishSnapshot()
        processNextIfNeeded()
    }

    func allocateQueueOrder() -> Int {
        let order = nextQueueOrder
        nextQueueOrder += 1
        return order
    }

    func publishSnapshot() {
        pendingProgressPublish?.cancel()
        pendingProgressPublish = nil
        lastProgressPublishDate = Date()
        let sorted = tasks.values.sorted { lhs, rhs in
            if lhs.state == .failed, rhs.state != .failed {
                return false
            }
            if lhs.state != .failed, rhs.state == .failed {
                return true
            }
            return lhs.queueOrder < rhs.queueOrder
        }
        updateScreenAwakeState()
        tasksPublisher.send(Array(sorted))
    }

    func cleanupTmpFile(for task: ActiveDownloadTask) {
        let finalURL = paths.absoluteAudioURL(for: task.destinationRelativePath)
        let tmpURL = Self.finalizingURL(for: finalURL)
        if FileManager.default.fileExists(atPath: tmpURL.path) {
            do {
                try FileManager.default.removeItem(at: tmpURL)
                AppLog.verbose(self, "cleanupTmpFile removed trackID=\(task.trackID)")
            } catch {
                AppLog.warning(
                    self, "cleanupTmpFile failed trackID=\(task.trackID) error=\(error.localizedDescription)",
                )
            }
        }
    }

    func cleanupLocalAudioArtifacts(for task: ActiveDownloadTask) {
        let finalURL = paths.absoluteAudioURL(for: task.destinationRelativePath)
        let cleanupTargets = [Self.finalizingURL(for: finalURL), finalURL]

        for fileURL in cleanupTargets where FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                try FileManager.default.removeItem(at: fileURL)
                AppLog.verbose(
                    self,
                    "cleanupLocalAudioArtifacts removed trackID=\(task.trackID) file=\(fileURL.lastPathComponent)",
                )
            } catch {
                AppLog.warning(
                    self,
                    "cleanupLocalAudioArtifacts failed trackID=\(task.trackID) file=\(fileURL.lastPathComponent) error=\(error.localizedDescription)",
                )
            }
        }
    }

    func updateScreenAwakeState() {
        let shouldKeepAwake = hasExecutingTasks
        guard shouldKeepAwake != isKeepingScreenAwake else {
            return
        }
        isKeepingScreenAwake = shouldKeepAwake
        screenAwakeHandler(shouldKeepAwake)
    }

    func updateDeferredState(for trackID: String) {
        guard !isPausedAll,
              let task = tasks[trackID],
              task.state == .waiting || task.state == .waitingForNetwork
        else {
            return
        }

        if shouldDeferForNetwork(trackID: trackID) {
            tasks[trackID]?.state = .waitingForNetwork
            persistRecord(trackID: trackID, state: .waitingForNetwork)
        } else {
            tasks[trackID]?.state = .waiting
            persistRecord(trackID: trackID, state: .queued)
        }
    }

    func updateDeferredStatesForPendingTasks() {
        for key in tasks.keys {
            updateDeferredState(for: key)
        }
    }
}
