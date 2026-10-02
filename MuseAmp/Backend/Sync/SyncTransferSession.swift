//
//  SyncTransferSession.swift
//  MuseAmp
//
//  Created by @Lakr233 on 2026/04/11.
//

import Foundation
import MuseAmpDatabaseKit
import UIKit

@MainActor
final class SyncTransferSession {
    nonisolated struct PartialDownloadError: Error {
        let downloadedURLs: [URL]
    }

    /// Shared by the sender's prepared copies (`am-transfer-<UUID>`) and the
    /// receiver's downloads (`am-transfer-receive-<UUID>`).
    nonisolated static let temporaryDirectoryPrefix = "am-transfer-"

    let paths: LibraryPaths
    let libraryDatabase: MusicLibraryDatabase
    let audioFileImporter: AudioFileImporter
    let apiClient: APIClient

    var onDiscoveredDevicesChanged: (([DiscoveredDevice]) -> Void) = { _ in }
    var onSenderProgressChanged: (@MainActor (SyncSenderTransferProgress) -> Void) = { _ in }

    private let preparedTrackBuilder: SyncPreparedTrackBuilder
    private let fileManager: FileManager

    private(set) var password = SyncPasswordGenerator.generate()
    private(set) var senderProgress: SyncSenderTransferProgress?
    private(set) var runningServer: SyncServer.RunningServer?

    private var preparedBatch: PreparedTransferBatch?
    private var server: SyncServer?
    private var advertiser: SyncBonjourAdvertiser?
    private var browser: SyncBonjourBrowser?
    private var receiverDirectoryURL: URL?
    private var advertisedBonjourToken = SyncBonjourIdentity.makeToken()

    init(
        paths: LibraryPaths,
        libraryDatabase: MusicLibraryDatabase,
        lyricsCacheStore: LyricsCacheStore,
        audioFileImporter: AudioFileImporter,
        apiClient: APIClient,
        fileManager: FileManager = .default,
    ) {
        self.paths = paths
        self.libraryDatabase = libraryDatabase
        self.audioFileImporter = audioFileImporter
        self.apiClient = apiClient
        self.fileManager = fileManager
        preparedTrackBuilder = SyncPreparedTrackBuilder(
            paths: paths,
            lyricsCacheStore: lyricsCacheStore,
            apiClient: apiClient,
            fileManager: fileManager,
        )
    }

    var deviceName: String {
        UIDevice.current.name
    }

    var advertisedDeviceName: String {
        SyncBonjourIdentity.makeAdvertisedDeviceName(
            baseName: deviceName,
            token: advertisedBonjourToken,
        )
    }

    var advertisedServiceName: String {
        SyncBonjourIdentity.makeAdvertisedServiceName(
            baseName: deviceName,
            token: advertisedBonjourToken,
        )
    }

    var discoveredDevices: [DiscoveredDevice] {
        browser?.devices ?? []
    }

    var currentConnectionInfo: SyncConnectionInfo? {
        guard let runningServer else {
            return nil
        }
        return SyncConnectionInfo(
            serviceName: runningServer.serviceName,
            password: password,
            deviceName: advertisedDeviceName,
            fallbackEndpoints: runningServer.preferredEndpoints,
            protocolVersion: SyncConstants.protocolVersion,
        )
    }

    var preparedSongCount: Int {
        preparedBatch?.manifest.entries.count ?? 0
    }

    var preparedSkippedItems: [PreparedTransferSkippedItem] {
        preparedBatch?.skippedItems ?? []
    }

    func prepareSender(
        tracks: [AudioTrackRecord],
        session: SyncPlaylistSession? = nil,
        password overridePassword: String? = nil,
        includeLyrics: Bool = false,
        progress: (@Sendable @MainActor (_ current: Int, _ total: Int) -> Void)? = nil,
    ) async throws {
        await stopSender()
        advertisedBonjourToken = SyncBonjourIdentity.makeToken()
        password = overridePassword ?? SyncPasswordGenerator.generate()
        AppLog.info(
            self,
            "prepareSender tracks=\(tracks.count) session=\(session != nil) passwordOverride=\(overridePassword != nil) passwordLength=\(password.count) includeLyrics=\(includeLyrics)",
        )
        senderProgress = nil
        preparedBatch = try await preparedTrackBuilder.prepareBatch(
            deviceName: deviceName,
            tracks: tracks,
            session: session,
            includeLyrics: includeLyrics,
            progress: progress,
        )
    }

    func prepareSender(
        playlist: Playlist,
        includeLyrics: Bool = false,
        progress: (@Sendable @MainActor (_ current: Int, _ total: Int) -> Void)? = nil,
    ) async throws -> SyncPlaylistTransferPlan {
        guard let plan = SyncPlaylistTransferPlan(
            playlist: playlist,
            database: libraryDatabase,
            paths: paths,
        ) else {
            throw SyncTransferError.noPreparedSongs
        }

        try await prepareSender(
            tracks: plan.transferableTracks,
            session: plan.session,
            includeLyrics: includeLyrics,
            progress: progress,
        )
        return plan
    }

    func startSender() async throws -> SyncServer.RunningServer {
        guard let preparedBatch else {
            throw SyncTransferError.noPreparedSongs
        }

        publishSenderProgress(
            .waiting(
                playlistName: preparedBatch.manifest.session?.playlistName,
                totalTrackCount: preparedBatch.manifest.entries.count,
            ),
        )

        let server = SyncServer(
            serviceName: advertisedServiceName,
            password: password,
            manifest: preparedBatch.manifest,
            preparedFiles: preparedBatch.filesByTrackID,
            onProgress: { [weak self] progress in
                Task { @MainActor [weak self] in
                    self?.publishSenderProgress(progress)
                }
            },
        )
        let runningServer = try await server.start()
        let advertiser = SyncBonjourAdvertiser()
        advertiser.start(
            serviceName: runningServer.serviceName,
            deviceName: advertisedDeviceName,
            port: runningServer.port,
            role: .sender,
        )

        self.server = server
        self.advertiser = advertiser
        self.runningServer = runningServer
        AppLog.info(self, "startSender prepared=\(preparedBatch.manifest.entries.count) port=\(runningServer.port)")
        return runningServer
    }

    func stopSender() async {
        advertiser?.stop()
        advertiser = nil
        await server?.stop()
        server = nil
        runningServer = nil
        senderProgress = nil
        preparedTrackBuilder.cleanup(batch: preparedBatch)
        preparedBatch = nil
    }

    func startBrowsing() {
        guard browser == nil else {
            browser?.start()
            return
        }

        let browser = SyncBonjourBrowser()
        browser.onDevicesChanged = { [weak self] devices in
            self?.onDiscoveredDevicesChanged(devices)
        }
        browser.start()
        self.browser = browser
    }

    func stopBrowsing() {
        browser?.stop()
        browser = nil
    }

    func resolveDevice(serviceName: String) async -> DiscoveredDevice? {
        await browser?.resolveService(named: serviceName)
    }

    func resolveEndpoints(for connectionInfo: SyncConnectionInfo) async -> [SyncEndpoint] {
        var endpoints: [SyncEndpoint] = []
        var seen = Set<SyncEndpoint>()

        if let resolvedDevice = await resolveDevice(serviceName: connectionInfo.serviceName) {
            let candidates = [resolvedDevice.preferredEndpoint].compactMap(\.self) + resolvedDevice.fallbackEndpoints
            for endpoint in candidates where !seen.contains(endpoint) {
                endpoints.append(endpoint)
                seen.insert(endpoint)
            }
        }

        for endpoint in connectionInfo.fallbackEndpoints where !seen.contains(endpoint) {
            endpoints.append(endpoint)
            seen.insert(endpoint)
        }

        return endpoints
    }

    func authenticate(
        endpoint: SyncEndpoint,
        password: String,
    ) async throws -> String {
        try await apiClient.authenticateTransfer(
            endpoint: endpoint,
            password: password,
            deviceName: deviceName,
        )
    }

    func fetchManifest(
        endpoint: SyncEndpoint,
        token: String,
    ) async throws -> SyncManifest {
        try await apiClient.fetchTransferManifest(
            endpoint: endpoint,
            token: token,
        )
    }

    func missingEntries(in manifest: SyncManifest) async -> [SyncManifestEntry] {
        let database = libraryDatabase
        let entries = manifest.entries
        let missing = await Task.detached(priority: .userInitiated) {
            entries.filter { entry in
                guard let existing = database.trackOrNil(byID: entry.trackID) else {
                    return true
                }
                return abs(entry.durationSeconds - existing.durationSeconds) > 1.0
            }
        }.value
        AppLog.info(self, "missingEntries total=\(entries.count) missing=\(missing.count)")
        return missing
    }

    func downloadEntries(
        endpoint: SyncEndpoint,
        token: String,
        entries: [SyncManifestEntry],
        progress: (@MainActor (
            _ current: Int,
            _ total: Int,
            _ entry: SyncManifestEntry,
            _ fractionCompleted: Double,
        ) -> Void)? = nil,
    ) async throws -> [URL] {
        let directoryURL: URL
        do {
            directoryURL = try prepareReceiverDirectoryURL()
        } catch {
            AppLog.error(self, "downloadEntries failed to prepare directory: \(error.localizedDescription)")
            throw error
        }

        AppLog.info(self, "downloadEntries begin endpoint=\(endpoint.displayString) entries=\(entries.count)")
        let client = apiClient
        var downloadedURLs: [URL] = []
        for (index, entry) in entries.enumerated() {
            if Task.isCancelled {
                AppLog.warning(
                    self,
                    "downloadEntries cancelled after \(downloadedURLs.count)/\(entries.count) file(s)",
                )
                throw PartialDownloadError(downloadedURLs: downloadedURLs)
            }

            let destinationURL = directoryURL.appendingPathComponent(
                "\(entry.trackID).\(entry.fileExtension.nilIfEmpty ?? "m4a")",
            )
            do {
                let url = try await client.downloadTransferTrack(
                    endpoint: endpoint,
                    token: token,
                    entry: entry,
                    to: destinationURL,
                    progress: { fractionCompleted in
                        progress?(index + 1, entries.count, entry, fractionCompleted)
                    },
                )
                downloadedURLs.append(url)
            } catch is CancellationError {
                AppLog.warning(
                    self,
                    "downloadEntries cancelled after \(downloadedURLs.count)/\(entries.count) file(s)",
                )
                throw PartialDownloadError(downloadedURLs: downloadedURLs)
            } catch let error as URLError where Self.isConnectionInterruption(error) {
                AppLog.warning(
                    self,
                    "downloadEntries connection interrupted after \(downloadedURLs.count)/\(entries.count) file(s) code=\(error.code.rawValue)",
                )
                throw PartialDownloadError(downloadedURLs: downloadedURLs)
            } catch {
                AppLog.warning(
                    self,
                    "downloadEntries skipped trackID=\(entry.trackID) error=\(error.localizedDescription)",
                )
            }
        }
        AppLog.info(
            self,
            "downloadEntries finished downloaded=\(downloadedURLs.count)/\(entries.count) endpoint=\(endpoint.displayString)",
        )
        return downloadedURLs
    }

    func importDownloadedFiles(
        _ urls: [URL],
        progress: (@MainActor (_ current: Int, _ total: Int) -> Void)? = nil,
    ) async -> AudioImportResult {
        AppLog.info(self, "importDownloadedFiles begin files=\(urls.count)")
        // Run in a fresh unstructured task: interrupted transfers import from a
        // cancelled task, and inherited cancellation would fail every file.
        let importer = audioFileImporter
        let result = await Task {
            await importer.importFiles(
                urls: urls,
                options: .offlineTransfer,
                progressCallback: progress,
            )
        }.value
        AppLog.info(
            self,
            "importDownloadedFiles finished succeeded=\(result.succeeded) duplicates=\(result.duplicates) errors=\(result.errors) noMetadata=\(result.noMetadata)",
        )
        return result
    }

    /// Tells the sender the receiver is done, so it can show completion even
    /// when songs the receiver already had were never requested. Older
    /// senders do not know this request; a failure does not affect the
    /// transfer that already finished.
    func reportTransferCompletion(
        endpoint: SyncEndpoint,
        token: String,
        alreadyInLibraryTrackCount: Int,
    ) async {
        // Run in a fresh unstructured task: the caller's transfer task is
        // cancelled when the user leaves the screen right after a receive,
        // and an inherited cancel would drop the request before it is sent.
        let apiClient = apiClient
        let result = await Task {
            try await apiClient.reportTransferCompletion(
                endpoint: endpoint,
                token: token,
                alreadyInLibraryTrackCount: alreadyInLibraryTrackCount,
            )
        }.result
        if case let .failure(error) = result {
            AppLog.warning(
                self,
                "reportTransferCompletion ignored failure endpoint=\(endpoint.displayString) error=\(error.localizedDescription)",
            )
        }
    }

    func stopReceiver() {
        stopBrowsing()
        cleanupReceiverDownloads()
    }

    func stopAll() async {
        await stopSender()
        stopReceiver()
    }

    /// Removes the `am-transfer-*` scratch directories (sender copies and
    /// receiver downloads) that a crash or kill left behind. Call it once at
    /// launch, before any transfer can create a new one.
    @discardableResult
    nonisolated static func removeStaleTemporaryDirectories(
        in directoryURL: URL = FileManager.default.temporaryDirectory,
        minimumAge: TimeInterval = staleTemporaryDirectoryMinimumAge,
    ) -> Int {
        let entries: [URL]
        do {
            entries = try FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.contentModificationDateKey],
            )
        } catch {
            AppLog.warning(
                "SyncTransferSession",
                "removeStaleTemporaryDirectories listing failed error=\(error.localizedDescription)",
            )
            return 0
        }

        var removedCount = 0
        for entry in entries where entry.lastPathComponent.hasPrefix(temporaryDirectoryPrefix) {
            if minimumAge > 0 {
                let modifiedAt: Date
                do {
                    modifiedAt = try entry.resourceValues(forKeys: [.contentModificationDateKey])
                        .contentModificationDate ?? .distantPast
                } catch {
                    AppLog.warning(
                        "SyncTransferSession",
                        "removeStaleTemporaryDirectories kept path=\(entry.lastPathComponent) error=\(error.localizedDescription)",
                    )
                    continue
                }
                guard Date().timeIntervalSince(modifiedAt) >= minimumAge else {
                    continue
                }
            }
            do {
                try FileManager.default.removeItem(at: entry)
                removedCount += 1
            } catch {
                AppLog.error(
                    "SyncTransferSession",
                    "removeStaleTemporaryDirectories failed path=\(entry.lastPathComponent) error=\(error.localizedDescription)",
                )
            }
        }
        if removedCount > 0 {
            AppLog.info("SyncTransferSession", "removeStaleTemporaryDirectories removed=\(removedCount)")
        }
        return removedCount
    }

    #if targetEnvironment(macCatalyst)
        /// An unsandboxed Mac build shares its temporary directory with other
        /// running copies of the app (debug builds, the test host), so only
        /// directories nobody has touched for an hour count as stale there.
        nonisolated static let staleTemporaryDirectoryMinimumAge: TimeInterval = 60 * 60
    #else
        nonisolated static let staleTemporaryDirectoryMinimumAge: TimeInterval = 0
    #endif
}

/// What one receive did with every song the sender offered:
/// `imported + skipped + failed` equals the number offered.
nonisolated struct SyncReceiveSummary: Equatable {
    let imported: Int
    let skipped: Int
    let failed: Int

    init(
        offeredCount: Int,
        requestedCount: Int,
        downloadedCount: Int,
        importResult: AudioImportResult,
    ) {
        imported = importResult.succeeded
        skipped = importResult.duplicates + max(offeredCount - requestedCount, 0)
        failed = importResult.errors
            + importResult.noMetadata
            + max(requestedCount - downloadedCount, 0)
    }
}

private extension SyncTransferSession {
    nonisolated static func isConnectionInterruption(_ error: URLError) -> Bool {
        switch error.code {
        case .cancelled,
             .cannotConnectToHost,
             .cannotFindHost,
             .networkConnectionLost,
             .notConnectedToInternet,
             .timedOut:
            true
        default:
            false
        }
    }

    func publishSenderProgress(_ progress: SyncSenderTransferProgress) {
        senderProgress = progress
        onSenderProgressChanged(progress)
    }

    func prepareReceiverDirectoryURL() throws -> URL {
        if let receiverDirectoryURL {
            return receiverDirectoryURL
        }

        let directoryURL = fileManager.temporaryDirectory
            .appendingPathComponent("\(Self.temporaryDirectoryPrefix)receive-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
        )
        receiverDirectoryURL = directoryURL
        return directoryURL
    }

    func cleanupReceiverDownloads() {
        guard let receiverDirectoryURL else {
            return
        }
        if fileManager.fileExists(atPath: receiverDirectoryURL.path) {
            do {
                try fileManager.removeItem(at: receiverDirectoryURL)
            } catch {
                AppLog.error(self, "cleanupReceiverDownloads failed path=\(receiverDirectoryURL.path) error=\(error.localizedDescription)")
            }
        }
        self.receiverDirectoryURL = nil
    }
}
