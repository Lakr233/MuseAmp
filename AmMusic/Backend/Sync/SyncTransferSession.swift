//
//  SyncTransferSession.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import AmMusicDatabaseKit
import Foundation
import UIKit

@MainActor
final class SyncTransferSession {
    let paths: LibraryPaths
    let libraryDatabase: MusicLibraryDatabase
    let lyricsCacheStore: LyricsCacheStore
    let audioFileImporter: AudioFileImporter
    let apiClient: APIClient

    var onDiscoveredDevicesChanged: (([DiscoveredDevice]) -> Void) = { _ in }

    private let preparedTrackBuilder: SyncPreparedTrackBuilder
    private let fileManager: FileManager

    private(set) var password = SyncPasswordGenerator.generate()
    private(set) var runningServer: SyncServer.RunningServer?
    private(set) var currentEndpoint: SyncEndpoint?

    private var preparedBatch: PreparedTransferBatch?
    private var server: SyncServer?
    private var advertiser: SyncBonjourAdvertiser?
    private var browser: SyncBonjourBrowser?
    private var receiverDirectoryURL: URL?

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
        self.lyricsCacheStore = lyricsCacheStore
        self.audioFileImporter = audioFileImporter
        self.apiClient = apiClient
        self.fileManager = fileManager
        preparedTrackBuilder = SyncPreparedTrackBuilder(
            paths: paths,
            fileManager: fileManager,
        )
    }

    var deviceName: String {
        UIDevice.current.name
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
            deviceName: deviceName,
            fallbackEndpoints: runningServer.preferredEndpoints,
        )
    }

    var preparedSongCount: Int {
        preparedBatch?.manifest.entries.count ?? 0
    }

    func prepareSender(
        tracks: [AudioTrackRecord],
        progress: (@MainActor (_ current: Int, _ total: Int) -> Void)? = nil,
    ) async throws {
        await stopSender()
        password = SyncPasswordGenerator.generate()
        preparedBatch = try await preparedTrackBuilder.prepareBatch(
            deviceName: deviceName,
            tracks: tracks,
            progress: progress,
        )
    }

    func startSender() async throws -> SyncServer.RunningServer {
        guard let preparedBatch else {
            throw SyncTransferError.noPreparedSongs
        }

        let server = SyncServer(
            serviceName: deviceName,
            password: password,
            manifest: preparedBatch.manifest,
            preparedFiles: preparedBatch.filesByTrackID,
        )
        let runningServer = try await server.start()
        let advertiser = SyncBonjourAdvertiser()
        advertiser.start(
            serviceName: runningServer.serviceName,
            deviceName: deviceName,
            port: runningServer.port,
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
        currentEndpoint = endpoint
        return try await apiClient.authenticateTransfer(
            endpoint: endpoint,
            password: password,
        )
    }

    func fetchManifest(
        endpoint: SyncEndpoint,
        token: String,
    ) async throws -> SyncManifest {
        currentEndpoint = endpoint
        return try await apiClient.fetchTransferManifest(
            endpoint: endpoint,
            token: token,
        )
    }

    func missingEntries(in manifest: SyncManifest) async -> [SyncManifestEntry] {
        let database = libraryDatabase
        let entries = manifest.entries
        return await Task.detached(priority: .userInitiated) {
            entries.filter { !database.hasTrack(byID: $0.trackID) }
        }.value
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
    ) async -> [URL] {
        currentEndpoint = endpoint
        let directoryURL: URL
        do {
            directoryURL = try prepareReceiverDirectoryURL()
        } catch {
            AppLog.error(self, "downloadEntries failed to prepare directory: \(error.localizedDescription)")
            return []
        }

        let client = apiClient
        return await Task.detached(priority: .userInitiated) {
            var downloadedURLs: [URL] = []
            for (index, entry) in entries.enumerated() {
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
                } catch {
                    AppLog.warning(
                        "SyncTransferSession",
                        "downloadEntries skipped trackID=\(entry.trackID) error=\(error.localizedDescription)",
                    )
                }
            }
            return downloadedURLs
        }.value
    }

    func importDownloadedFiles(
        _ urls: [URL],
        progress: (@MainActor (_ current: Int, _ total: Int) -> Void)? = nil,
    ) async -> AudioImportResult {
        await audioFileImporter.importFiles(
            urls: urls,
            progressCallback: progress,
        )
    }

    func stopReceiver() {
        stopBrowsing()
        cleanupReceiverDownloads()
        currentEndpoint = nil
    }

    func stopAll() async {
        await stopSender()
        stopReceiver()
    }
}

private extension SyncTransferSession {
    func prepareReceiverDirectoryURL() throws -> URL {
        if let receiverDirectoryURL {
            return receiverDirectoryURL
        }

        let directoryURL = fileManager.temporaryDirectory
            .appendingPathComponent("am-transfer-receive-\(UUID().uuidString)", isDirectory: true)
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
