import AmMusicDatabaseKit
import Digger
import Foundation

// MARK: - Digger Integration

extension DownloadManager {
    func syncDiggerHTTPHeadersIfNeeded() {
        let headers = apiClient.downloadHTTPHeaders()
        guard DiggerManager.shared.additionalHTTPHeaders != headers else {
            return
        }
        DiggerManager.shared.additionalHTTPHeaders = headers
    }

    func startDiggerDownload(for task: ActiveDownloadTask) {
        guard let url = task.url else {
            AppLog.error(self, "startDiggerDownload missing URL for trackID=\(task.trackID)")
            return
        }
        diggerStartedURLs.insert(url)
        DiggerManager.shared.download(with: url)
            .progress { [weak self] progress in
                self?.handleProgress(trackID: task.trackID, progress: progress)
            }
            .speed { [weak self] speed in
                self?.handleSpeed(trackID: task.trackID, speed: speed)
            }
            .completion { [weak self] result in
                self?.handleCompletion(trackID: task.trackID, result: result)
            }
    }

    func handleProgress(trackID: String, progress: Progress) {
        guard tasks[trackID] != nil else {
            return
        }

        let fraction: Double =
            if progress.totalUnitCount > 0 {
                Double(progress.completedUnitCount) / Double(progress.totalUnitCount)
            } else {
                -1
            }

        tasks[trackID]?.progress = fraction

        if let url = tasks[trackID]?.url, !hasMarkedDownloading.contains(url) {
            hasMarkedDownloading.insert(url)
            let persistedProgress = max(fraction, 0)
            persistRecord(trackID: trackID, state: .downloading, progress: persistedProgress)
        }

        scheduleProgressPublish()
    }

    func handleSpeed(trackID: String, speed: Int64) {
        guard tasks[trackID] != nil else {
            return
        }
        tasks[trackID]?.speed = speed
        scheduleProgressPublish()
    }

    func scheduleProgressPublish() {
        guard pendingProgressPublish == nil else { return }
        let now = Date()
        let elapsed = now.timeIntervalSince(lastProgressPublishDate)
        if elapsed >= 0.2 {
            lastProgressPublishDate = now
            publishSnapshot()
        } else {
            let delay = 0.2 - elapsed
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                pendingProgressPublish = nil
                lastProgressPublishDate = Date()
                publishSnapshot()
            }
            pendingProgressPublish = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    func handleCompletion(trackID: String, result: Digger.Result<URL>) {
        guard let task = tasks[trackID] else {
            AppLog.warning(self, "handleCompletion ignored: task not found for trackID=\(trackID)")
            return
        }

        switch result {
        case let .success(cachedFileURL):
            let finalURL = paths.absoluteAudioURL(for: task.destinationRelativePath)
            let tmpURL = Self.finalizingURL(for: finalURL)

            do {
                let destDir = tmpURL.deletingLastPathComponent()
                try FileManager.default.createDirectory(
                    at: destDir,
                    withIntermediateDirectories: true
                )
                if FileManager.default.fileExists(atPath: tmpURL.path) {
                    try FileManager.default.removeItem(at: tmpURL)
                }
                try FileManager.default.moveItem(at: cachedFileURL, to: tmpURL)

                startFinalizing(trackID: trackID, fileURL: tmpURL)
            } catch {
                AppLog.error(self, "File move failed for trackID=\(trackID): \(error.localizedDescription)")
                tasks[trackID]?.markFailed()
                persistRecord(trackID: trackID, state: .failed, lastError: error.localizedDescription)
            }

            if let url = task.url {
                hasMarkedDownloading.remove(url)
                diggerStartedURLs.remove(url)
            }
            intentionallyPaused.remove(trackID)

        case let .failure(error):
            let nsError = error as NSError
            if nsError.code == NSURLErrorCancelled, intentionallyPaused.contains(trackID) {
                return
            }
            if nsError.code == NSURLErrorCancelled {
                let currentRetry = tasks[trackID]?.retryCount ?? 0
                if currentRetry < 3 {
                    AppLog.warning(
                        self,
                        "Download cancelled unexpectedly for trackID=\(trackID), requeuing (retry \(currentRetry + 1)/3)"
                    )
                    tasks[trackID]?.retryCount = currentRetry + 1
                    tasks[trackID]?.state = .waiting
                    tasks[trackID]?.url = nil
                    persistRecord(trackID: trackID, state: .queued)
                    if let url = task.url {
                        hasMarkedDownloading.remove(url)
                        diggerStartedURLs.remove(url)
                    }
                    publishSnapshot()
                    processNextIfNeeded()
                    return
                }
                AppLog.error(
                    self,
                    "Download cancelled repeatedly for trackID=\(trackID), marking failed after \(currentRetry) retries"
                )
            }
            AppLog.error(self, "Download failed trackID=\(trackID): \(error.localizedDescription)")
            tasks[trackID]?.markFailed()
            persistRecord(trackID: trackID, state: .failed, lastError: error.localizedDescription)
            if let url = task.url {
                hasMarkedDownloading.remove(url)
                diggerStartedURLs.remove(url)
            }
            cleanupTmpFile(for: task)
        }

        publishSnapshot()
        processNextIfNeeded()
    }

    func startFinalizing(trackID: String, fileURL: URL) {
        guard let task = tasks[trackID] else {
            AppLog.warning(self, "startFinalizing missing task for trackID=\(trackID)")
            return
        }

        let finalURL = paths.absoluteAudioURL(for: task.destinationRelativePath)
        let tmpURL = Self.finalizingURL(for: finalURL)
        let ingestURL: URL
        if fileURL == finalURL {
            do {
                if FileManager.default.fileExists(atPath: tmpURL.path) {
                    try FileManager.default.removeItem(at: tmpURL)
                }
                try FileManager.default.moveItem(at: finalURL, to: tmpURL)
                ingestURL = tmpURL
            } catch {
                AppLog.error(
                    self,
                    "startFinalizing staging move failed trackID=\(trackID) error=\(error.localizedDescription)"
                )
                tasks[trackID]?.markFailed()
                persistRecord(trackID: trackID, state: .failed, lastError: error.localizedDescription)
                publishSnapshot()
                processNextIfNeeded()
                return
            }
        } else {
            ingestURL = fileURL
        }

        tasks[trackID]?.state = .finalizing
        tasks[trackID]?.progress = 1
        tasks[trackID]?.speed = 0
        persistRecord(
            trackID: trackID,
            state: .finalizing,
            progress: 1,
            localRelativePath: task.destinationRelativePath
        )
        AppLog.info(
            self, "Download finalizing trackID=\(trackID) relativePath=\(task.destinationRelativePath)"
        )
        publishSnapshot()

        let artworkURL = task.artworkURL
        let albumID = task.albumID
        let title = task.title
        let artistName = task.artistName
        let albumName = task.albumName
        let databaseManager = databaseManager
        let apiClient = apiClient
        let paths = paths
        let lyricsCacheStore = lyricsCacheStore
        Task(priority: .utility) { [weak self] in
            async let artworkDone: Void = DownloadArtworkProcessor.prepareDownloadedTrack(
                trackID: trackID,
                fileURL: ingestURL,
                artworkURL: artworkURL,
                apiClient: apiClient,
                locations: paths
            )
            async let lyricsDone: Void = DownloadLyricsProcessor.cacheLyrics(
                trackID: trackID,
                apiClient: apiClient,
                lyricsStore: lyricsCacheStore
            )
            _ = await (artworkDone, lyricsDone)

            let lyrics = lyricsCacheStore.lyrics(for: trackID)
            var exportInfo = ExportMetadataProcessor.ExportInfo(trackID: trackID, albumID: albumID)
            exportInfo.artworkURL = artworkURL
            exportInfo.lyrics = lyrics
            exportInfo.title = title
            exportInfo.artistName = artistName
            exportInfo.albumName = albumName
            do {
                try await ExportMetadataProcessor.embedExportMetadata(exportInfo, into: ingestURL)
                AppLog.info("DownloadManager", "Metadata embedded trackID=\(trackID)")
            } catch {
                AppLog.warning(
                    "DownloadManager",
                    "Metadata embed failed trackID=\(trackID): \(error.localizedDescription)"
                )
            }

            let metadata = ImportedTrackMetadata(
                trackID: trackID,
                albumID: albumID,
                title: title,
                artistName: artistName,
                albumTitle: albumName ?? String(localized: "Unknown Album"),
                albumArtistName: nil,
                durationSeconds: nil,
                trackNumber: nil,
                discNumber: nil,
                genreName: nil,
                composerName: nil,
                releaseDate: nil,
                lyrics: lyrics,
                sourceKind: .downloaded
            )

            do {
                _ = try await databaseManager.send(.ingestAudioFile(url: ingestURL, metadata: metadata))
                await self?.completeFinalization(trackID: trackID, ingestionError: nil)
            } catch {
                await self?.completeFinalization(trackID: trackID, ingestionError: error)
            }
        }
    }
}
