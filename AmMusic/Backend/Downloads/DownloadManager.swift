import AmMusicDatabaseKit
import Combine
import Digger
import Foundation

nonisolated struct ActiveDownloadTask: Identifiable, Equatable {
    let id: String
    let trackID: String
    let albumID: String
    var url: URL?
    let title: String
    let artistName: String
    let albumName: String?
    let artworkURL: URL?
    let destinationRelativePath: String
    var progress: Double
    var speed: Int64
    var retryCount: Int
    var state: State
    let queueOrder: Int

    mutating func markFailed() {
        state = .failed
        progress = 0
        speed = 0
    }

    enum State: Equatable {
        case waiting
        case waitingForNetwork
        case resolving
        case downloading
        case finalizing
        case paused
        case failed

        var sortOrder: Int {
            switch self {
            case .downloading: 0
            case .finalizing: 1
            case .resolving: 2
            case .waitingForNetwork: 3
            case .paused: 4
            case .waiting: 5
            case .failed: 6
            }
        }
    }
}

@MainActor
final class DownloadManager {
    let paths: LibraryPaths
    let databaseManager: DatabaseManager
    let downloadStore: DownloadStore
    let apiClient: APIClient
    let lyricsCacheStore: LyricsCacheStore
    let networkMonitor: NetworkMonitor
    let screenAwakeHandler: @MainActor (Bool) -> Void

    let tasksPublisher = CurrentValueSubject<[ActiveDownloadTask], Never>([])
    var isPausedAll = false
    var isPausedForNetwork = false

    let maxConcurrent = 1
    var tasks: [String: ActiveDownloadTask] = [:]
    var nextQueueOrder = 0
    var hasMarkedDownloading: Set<URL> = []
    var diggerStartedURLs: Set<URL> = []

    var intentionallyPaused: Set<String> = []
    var cellularAllowedTrackIDs: Set<String> = []
    var networkCancellable: AnyCancellable?
    var isKeepingScreenAwake = false

    var lastProgressPublishDate: Date = .distantPast
    var pendingProgressPublish: DispatchWorkItem?

    init(
        paths: LibraryPaths,
        databaseManager: DatabaseManager,
        downloadStore: DownloadStore,
        apiClient: APIClient,
        lyricsCacheStore: LyricsCacheStore,
        networkMonitor: NetworkMonitor,
        screenAwakeHandler: @escaping @MainActor (Bool) -> Void
    ) {
        self.paths = paths
        self.databaseManager = databaseManager
        self.downloadStore = downloadStore
        self.apiClient = apiClient
        self.lyricsCacheStore = lyricsCacheStore
        self.networkMonitor = networkMonitor
        self.screenAwakeHandler = screenAwakeHandler

        DiggerManager.shared.logLevel = .none
        DiggerManager.shared.maxConcurrentTasksCount = 1
        syncDiggerHTTPHeadersIfNeeded()

        observeNetworkChanges()
    }

    func reconcileOnLaunch() {
        let active = downloadStore.activeRecords()
        if !active.isEmpty {
            AppLog.info(self, "Reconciling active downloads on launch count=\(active.count)")
        }
        for record in active {
            if record.status == .downloading || record.status == .resolving {
                AppLog.info(
                    self,
                    "Record \(record.trackID) was in status \(record.status), rehydrating as waiting (interrupted)"
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
                    progress: record.progress,
                    retryCount: record.retryCount,
                    errorMessage: record.errorMessage,
                    createdAt: record.createdAt,
                    updatedAt: Date()
                )
                downloadStore.upsert(queuedRecord)
                rehydrateQueuedRecord(queuedRecord)
            } else if record.status == .waitingForNetwork {
                AppLog.info(self, "Record \(record.trackID) was waiting for network, rehydrating")
                rehydrateQueuedRecord(record)
            } else if record.status == .finalizing {
                AppLog.info(self, "Record \(record.trackID) was finalizing, resuming finalization")
                rehydrateFinalizingRecord(record)
            } else if record.status == .queued {
                AppLog.info(self, "Record \(record.trackID) was queued, rehydrating to waiting")
                rehydrateQueuedRecord(record)
            }
        }

        let failed = downloadStore.failedRecords()
        for record in failed {
            rehydrateFailedRecord(record)
        }

        publishSnapshot()
        processNextIfNeeded()
    }

    // MARK: - Public API

    struct SubmitResult {
        var queued: Int = 0
        var skipped: Int = 0
    }

    @discardableResult
    func submitRequests(_ requests: [SongDownloadRequest]) -> SubmitResult {
        var result = SubmitResult()

        for request in requests {
            if tasks[request.trackID] != nil {
                result.skipped += 1
                continue
            }

            if downloadStore.isDownloaded(trackID: request.trackID) {
                AppLog.info(self, "submitRequests already downloaded trackID=\(request.trackID)")
                result.skipped += 1
                continue
            }

            if let existingRecord = downloadStore.record(trackID: request.trackID) {
                if existingRecord.status == .failed {
                    AppLog.warning(self, "submitRequests removing failed record trackID=\(request.trackID)")
                    downloadStore.deleteRecords(trackIDs: [request.trackID])
                } else {
                    result.skipped += 1
                    continue
                }
            }

            let albumFolder = sanitizePathComponent(request.albumID)
            let filename = sanitizePathComponent(request.trackID) + ".m4a"
            let destPath = "\(albumFolder)/\(filename)"

            let job = DownloadJob(
                jobID: UUID().uuidString,
                trackID: request.trackID,
                albumID: request.albumID,
                targetRelativePath: destPath,
                title: request.title,
                artistName: request.artistName,
                albumTitle: request.albumName,
                artworkURL: request.artworkURL?.absoluteString,
                status: .queued,
                progress: 0
            )
            downloadStore.upsert(job)

            let task = ActiveDownloadTask(
                id: job.jobID,
                trackID: request.trackID,
                albumID: request.albumID,
                title: request.title,
                artistName: request.artistName,
                albumName: request.albumName,
                artworkURL: request.artworkURL,
                destinationRelativePath: destPath,
                progress: 0,
                speed: 0,
                retryCount: 0,
                state: .waiting,
                queueOrder: allocateQueueOrder()
            )
            tasks[request.trackID] = task
            updateDeferredState(for: request.trackID)
            result.queued += 1
        }

        AppLog.info(self, "submitRequests result queued=\(result.queued) skipped=\(result.skipped)")
        publishSnapshot()
        processNextIfNeeded()
        return result
    }

    func pauseAll() {
        isPausedAll = true
        var affectedCount = 0
        for key in tasks.keys {
            guard let state = tasks[key]?.state else { continue }
            if state == .downloading {
                intentionallyPaused.insert(key)
                tasks[key]?.state = .paused
                tasks[key]?.speed = 0
                affectedCount += 1
            }
        }
        AppLog.info(self, "Paused \(affectedCount) downloading tasks")
        DiggerManager.shared.stopAllTasks()
        publishSnapshot()
    }

    func resumeAll() {
        isPausedAll = false
        var resumedCount = 0
        for key in tasks.keys {
            if tasks[key]?.state == .paused {
                intentionallyPaused.remove(key)
                tasks[key]?.state = .waiting
                resumedCount += 1
            }
        }
        AppLog.info(self, "Resumed \(resumedCount) paused tasks")
        if networkMonitor.isWiFi {
            isPausedForNetwork = false
        }
        publishSnapshot()
        processNextIfNeeded()
    }

    func retryFailed(trackID: String) {
        guard var task = tasks[trackID], task.state == .failed else { return }
        AppLog.info(self, "retryFailed trackID=\(trackID)")
        let finalURL = paths.absoluteAudioURL(for: task.destinationRelativePath)
        let tmpURL = Self.finalizingURL(for: finalURL)
        let finalizationURL = FileManager.default.fileExists(atPath: tmpURL.path) ? tmpURL : finalURL
        if FileManager.default.fileExists(atPath: finalizationURL.path) {
            task.state = .finalizing
            task.progress = 1
            task.speed = 0
            task.retryCount += 1
            tasks[trackID] = task
            persistRecord(
                trackID: trackID,
                state: .finalizing,
                progress: 1,
                localRelativePath: task.destinationRelativePath,
                retryCount: task.retryCount
            )
            publishSnapshot()
            startFinalizing(trackID: trackID, fileURL: finalizationURL)
            processNextIfNeeded()
            return
        }
        task.state = .waiting
        task.url = nil
        task.progress = 0
        task.speed = 0
        task.retryCount += 1
        tasks[trackID] = task
        persistRecord(trackID: trackID, state: .queued)
        publishSnapshot()
        processNextIfNeeded()
    }

    func removeFailed(trackID: String) {
        guard let task = tasks[trackID], task.state == .failed else { return }
        AppLog.info(self, "removeFailed trackID=\(trackID)")
        cleanupTmpFile(for: task)
        tasks.removeValue(forKey: trackID)
        downloadStore.deleteRecords(trackIDs: [trackID])
        publishSnapshot()
    }

    func cancelTask(trackID: String) {
        guard let task = tasks[trackID] else { return }
        AppLog.info(self, "cancelTask trackID=\(trackID) state=\(task.state)")
        if task.state == .downloading, let url = task.url {
            DiggerManager.shared.stopTask(for: url)
        }
        cleanupTmpFile(for: task)
        intentionallyPaused.remove(trackID)
        cellularAllowedTrackIDs.remove(trackID)
        tasks.removeValue(forKey: trackID)
        downloadStore.deleteRecords(trackIDs: [trackID])
        publishSnapshot()
        processNextIfNeeded()
    }

    func allowCellularDownload(trackID: String) {
        cellularAllowedTrackIDs.insert(trackID)
        guard networkMonitor.connectionType == .cellular, !isPausedAll else { return }

        if let task = tasks[trackID] {
            if task.state == .waitingForNetwork {
                tasks[trackID]?.state = .waiting
                persistRecord(trackID: trackID, state: .queued)
                AppLog.info(self, "Allowing cellular download trackID=\(trackID)")
            }
        }
        publishSnapshot()
        processNextIfNeeded()
    }
}
