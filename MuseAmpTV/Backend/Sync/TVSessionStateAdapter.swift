//
//  TVSessionStateAdapter.swift
//  MuseAmpTV
//
//  Created by @Lakr233 on 2026/04/11.
//

import Foundation
import UIKit

@MainActor
final class TVSessionStateAdapter {
    private enum TransferPhase {
        case waiting
        case connecting
        case receiving(
            sourceDeviceName: String,
            receivedTrackCount: Int,
            totalTrackCount: Int,
            currentTrackTitle: String?,
        )
        case importing(sourceDeviceName: String, currentTrackCount: Int, totalTrackCount: Int)
        case disconnected(
            playlistSession: SyncPlaylistSession,
            endpoint: SyncEndpoint,
            token: String,
            manifest: SyncManifest,
            downloadedURLs: [URL],
        )
        case failed(String)
    }

    private let context: TVAppContext
    private let receiverAdvertiser = SyncBonjourAdvertiser()
    private var transferPhase: TransferPhase = .waiting
    private var transferTask: Task<Void, Never>?

    var onStateChanged: () -> Void = {}
    var onConnectResult: (_ success: Bool, _ errorMessage: String?) -> Void = { _, _ in }

    private var transferReadyContinuation: CheckedContinuation<Void, Never>?

    init(context: TVAppContext) {
        self.context = context
    }

    var discoveredDevices: [DiscoveredDevice] {
        context.syncTransferSession.discoveredDevices.sorted {
            $0.deviceName.localizedCaseInsensitiveCompare($1.deviceName) == .orderedAscending
        }
    }

    func activate() {
        context.syncTransferSession.onDiscoveredDevicesChanged = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.notifyStateChanged()
            }
        }
        syncReceiverAvailability()
        notifyStateChanged()
    }

    var isDisconnectedTransfer: Bool {
        if case .disconnected = transferPhase {
            return true
        }
        return false
    }

    func refreshDiscovery() {
        switch transferPhase {
        case .failed, .disconnected:
            transferPhase = .waiting
        default:
            break
        }
        syncReceiverAvailability()
        notifyStateChanged()
    }

    func retryTransfer() {
        guard case let .disconnected(
            playlistSession, endpoint, token, manifest, previousURLs,
        ) = transferPhase else { return }

        transferTask?.cancel()
        transferTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await resumeTransfer(
                playlistSession: playlistSession,
                endpoint: endpoint,
                token: token,
                manifest: manifest,
                previousDownloadedURLs: previousURLs,
            )
        }
    }

    func syncReceiverAvailability() {
        let shouldAdvertiseReceiver: Bool = switch transferPhase {
        case .connecting, .receiving, .importing, .disconnected:
            false
        case .waiting, .failed:
            context.currentSessionManifest == nil
        }

        guard shouldAdvertiseReceiver else {
            receiverAdvertiser.stop()
            context.syncTransferSession.stopBrowsing()
            return
        }

        receiverAdvertiser.start(
            serviceName: context.receiverHandshakeInfo.serviceName,
            deviceName: context.receiverHandshakeInfo.deviceName,
            port: 1,
            role: .receiver,
        )
        context.syncTransferSession.startBrowsing()
    }

    var sessionState: AMTVLibrarySessionState {
        let trackCount = context.currentSessionTrackCount
        let snapshot = context.playbackController.snapshot

        if snapshot.currentTrack != nil {
            return .playing
        }

        switch transferPhase {
        case .receiving, .importing:
            return .receivingTracks
        case let .failed(message):
            if trackCount == 0 {
                return .failed(message: message)
            }
        case let .disconnected(playlistSession, _, _, _, _):
            if trackCount == 0 {
                return .failed(
                    message: String(localized: "Connection lost while receiving \"\(playlistSession.playlistName)\"."),
                )
            }
        case .waiting, .connecting:
            break
        }

        if trackCount > 0 {
            return .playing
        }
        return .awaitingUpload
    }

    var uploadWaitingContent: AMTVUploadWaitingContent {
        let message = if case .connecting = transferPhase {
            String(localized: "Authenticating with the selected iPhone sender and preparing the transfer manifest for this Apple TV session.")
        } else {
            String(localized: "On an iPhone with Muse Amp installed, use the system camera to scan the QR code displayed on this Apple TV, then select the songs to transfer.")
        }
        return AMTVUploadWaitingContent(message: message, qrPayload: receiverHandshakePayload())
    }

    var receivingTracksContent: AMTVReceivingTracksContent? {
        switch transferPhase {
        case let .receiving(sourceDeviceName, receivedTrackCount, totalTrackCount, currentTrackTitle):
            AMTVReceivingTracksContent(
                sourceDeviceName: sourceDeviceName,
                receivedTrackCount: receivedTrackCount,
                totalTrackCount: totalTrackCount,
                currentTrackTitle: currentTrackTitle,
            )
        case let .importing(sourceDeviceName, currentTrackCount, totalTrackCount):
            AMTVReceivingTracksContent(
                sourceDeviceName: sourceDeviceName,
                receivedTrackCount: currentTrackCount,
                totalTrackCount: totalTrackCount,
                currentTrackTitle: String(localized: "Saving playlist session"),
            )
        case .waiting, .connecting, .disconnected, .failed:
            nil
        }
    }

    func connect(to device: DiscoveredDevice, password: String) {
        transferTask?.cancel()
        transferTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            let endpoints = [device.preferredEndpoint].compactMap(\.self) + device.fallbackEndpoints
            await runTransfer(sourceDeviceName: device.deviceName, endpoints: endpoints, password: password)
        }
    }

    func proceedWithTransfer() {
        transferReadyContinuation?.resume()
        transferReadyContinuation = nil
    }

    func cancelTransfer() {
        transferTask?.cancel()
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            await context.syncTransferSession.stopAll()
            transferPhase = .waiting
            syncReceiverAvailability()
            notifyStateChanged()
        }
    }

    func resetSession() {
        transferTask?.cancel()
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            await context.clearSessionLibrary()
            transferPhase = .waiting
            syncReceiverAvailability()
            notifyStateChanged()
        }
    }
}

private extension TVSessionStateAdapter {
    func runTransfer(
        sourceDeviceName: String,
        endpoints: [SyncEndpoint],
        password: String,
    ) async {
        transferPhase = .connecting
        receiverAdvertiser.stop()
        notifyStateChanged()

        let session = context.syncTransferSession
        guard !endpoints.isEmpty else {
            transferPhase = .failed(SyncTransferError.noResolvableEndpoint.localizedDescription)
            notifyStateChanged()
            return
        }

        var lastErrorMessage = SyncTransferError.noResolvableEndpoint.localizedDescription

        for endpoint in endpoints {
            if Task.isCancelled {
                return
            }

            do {
                let token = try await session.authenticate(endpoint: endpoint, password: password)
                onConnectResult(true, nil)
                await withCheckedContinuation { continuation in
                    transferReadyContinuation = continuation
                }
                guard !Task.isCancelled else { return }
                try await receiveTransfer(session: session, endpoint: endpoint, token: token)
                return
            } catch {
                AppLog.warning(
                    self,
                    "runTransfer failed endpoint=\(endpoint.displayString) source=\(sourceDeviceName) error=\(error.localizedDescription)",
                )
                lastErrorMessage = error.localizedDescription
            }
        }

        onConnectResult(false, lastErrorMessage)
        session.stopReceiver()
        transferPhase = .failed(lastErrorMessage)
        notifyStateChanged()
    }

    func receiveTransfer(
        session: SyncTransferSession,
        endpoint: SyncEndpoint,
        token: String,
    ) async throws {
        AppLog.info(self, "receiveTransfer begin endpoint=\(endpoint.displayString)")
        let manifest = try await session.fetchManifest(endpoint: endpoint, token: token)
        AppLog.info(
            self,
            "receiveTransfer manifest entries=\(manifest.entries.count) session=\(manifest.session != nil) device=\(sanitizedLogText(manifest.deviceName))",
        )
        if Task.isCancelled {
            AppLog.warning(self, "receiveTransfer cancelled after fetching manifest")
            return
        }

        guard let playlistSession = manifest.session else {
            AppLog.error(self, "receiveTransfer manifest missing playlist session")
            throw SyncTransferError.invalidPlaylistSession
        }

        let missingEntries = await session.missingEntries(in: manifest)
        AppLog.info(self, "receiveTransfer missingEntries=\(missingEntries.count)/\(manifest.entries.count)")
        if missingEntries.isEmpty {
            AppLog.info(self, "receiveTransfer allTracksExist, saving session directly")
            session.stopReceiver()
            let didSaveSession = await context.completeTransferredPlaylistSession(
                from: manifest,
                autoPlay: true,
            )
            guard didSaveSession else {
                let message = context.takePendingSessionAlertMessage()
                    ?? SyncTransferError.invalidPlaylistSession.localizedDescription
                AppLog.error(self, "receiveTransfer completeSession failed (no missing) message=\(message)")
                transferPhase = .failed(message)
                syncReceiverAvailability()
                notifyStateChanged()
                return
            }
            transferPhase = .waiting
            notifyStateChanged()
            await session.reportTransferCompletion(
                endpoint: endpoint,
                token: token,
                alreadyInLibraryTrackCount: manifest.entries.count,
            )
            return
        }

        transferPhase = .receiving(
            sourceDeviceName: manifest.deviceName,
            receivedTrackCount: 0,
            totalTrackCount: missingEntries.count,
            currentTrackTitle: nil,
        )
        notifyStateChanged()

        let downloadedURLs: [URL]
        do {
            downloadedURLs = try await session.downloadEntries(
                endpoint: endpoint,
                token: token,
                entries: missingEntries,
                progress: { [weak self] current, total, entry, _ in
                    guard let self else {
                        return
                    }
                    transferPhase = .receiving(
                        sourceDeviceName: manifest.deviceName,
                        receivedTrackCount: current,
                        totalTrackCount: total,
                        currentTrackTitle: String(localized: "\(entry.artistName) - \(entry.title)"),
                    )
                    notifyStateChanged()
                },
            )
        } catch let error as SyncTransferSession.PartialDownloadError {
            AppLog.warning(
                self,
                "receiveTransfer cancelled after partial download count=\(error.downloadedURLs.count)",
            )
            downloadedURLs = error.downloadedURLs
        }

        AppLog.info(self, "receiveTransfer downloadPhase done downloaded=\(downloadedURLs.count)/\(missingEntries.count)")

        if Task.isCancelled {
            AppLog.warning(self, "receiveTransfer cancelled after downloads")
            return
        }

        let downloadFailureCount = missingEntries.count - downloadedURLs.count
        if isLikelyDisconnect(failureCount: downloadFailureCount, requestedCount: missingEntries.count) {
            AppLog.warning(
                self,
                "receiveTransfer disconnect detected failures=\(downloadFailureCount)/\(missingEntries.count), offering retry",
            )
            transferPhase = .disconnected(
                playlistSession: playlistSession,
                endpoint: endpoint,
                token: token,
                manifest: manifest,
                downloadedURLs: downloadedURLs,
            )
            notifyStateChanged()
            return
        }

        await importAndComplete(
            session: session,
            endpoint: endpoint,
            token: token,
            manifest: manifest,
            playlistSession: playlistSession,
            missingEntries: missingEntries,
            downloadedURLs: downloadedURLs,
        )
    }

    func resumeTransfer(
        playlistSession: SyncPlaylistSession,
        endpoint: SyncEndpoint,
        token: String,
        manifest: SyncManifest,
        previousDownloadedURLs: [URL],
    ) async {
        let completedEntryTrackIDs = Set(previousDownloadedURLs.map { $0.deletingPathExtension().lastPathComponent })
        let session = context.syncTransferSession
        let missingEntries = await session.missingEntries(in: manifest)
        let remainingEntries = missingEntries.filter {
            !completedEntryTrackIDs.contains($0.trackID)
        }

        if remainingEntries.isEmpty {
            AppLog.info(self, "resumeTransfer all entries already downloaded, proceeding to import")
            await importAndComplete(
                session: session,
                endpoint: endpoint,
                token: token,
                manifest: manifest,
                playlistSession: playlistSession,
                missingEntries: missingEntries,
                downloadedURLs: previousDownloadedURLs,
            )
            return
        }

        let alreadyDownloaded = completedEntryTrackIDs.count
        transferPhase = .receiving(
            sourceDeviceName: manifest.deviceName,
            receivedTrackCount: alreadyDownloaded,
            totalTrackCount: missingEntries.count,
            currentTrackTitle: String(localized: "Resuming transfer..."),
        )
        notifyStateChanged()

        let newDownloadedURLs: [URL]
        do {
            newDownloadedURLs = try await session.downloadEntries(
                endpoint: endpoint,
                token: token,
                entries: remainingEntries,
                progress: { [weak self] current, _, entry, _ in
                    guard let self else { return }
                    let adjustedCurrent = alreadyDownloaded + current
                    let adjustedTotal = missingEntries.count
                    transferPhase = .receiving(
                        sourceDeviceName: manifest.deviceName,
                        receivedTrackCount: adjustedCurrent,
                        totalTrackCount: adjustedTotal,
                        currentTrackTitle: String(localized: "\(entry.artistName) - \(entry.title)"),
                    )
                    notifyStateChanged()
                },
            )
        } catch let error as SyncTransferSession.PartialDownloadError {
            AppLog.warning(self, "resumeTransfer partial download count=\(error.downloadedURLs.count)")
            newDownloadedURLs = error.downloadedURLs
        } catch {
            AppLog.error(self, "resumeTransfer failed: \(error)")
            newDownloadedURLs = []
        }

        if Task.isCancelled {
            AppLog.warning(self, "resumeTransfer cancelled after downloads")
            return
        }

        let allDownloadedURLs = previousDownloadedURLs + newDownloadedURLs

        let resumeFailureCount = remainingEntries.count - newDownloadedURLs.count
        if isLikelyDisconnect(failureCount: resumeFailureCount, requestedCount: remainingEntries.count) {
            AppLog.warning(self, "resumeTransfer disconnect again failures=\(resumeFailureCount)/\(remainingEntries.count)")
            transferPhase = .disconnected(
                playlistSession: playlistSession,
                endpoint: endpoint,
                token: token,
                manifest: manifest,
                downloadedURLs: allDownloadedURLs,
            )
            notifyStateChanged()
            return
        }

        await importAndComplete(
            session: session,
            endpoint: endpoint,
            token: token,
            manifest: manifest,
            playlistSession: playlistSession,
            missingEntries: missingEntries,
            downloadedURLs: allDownloadedURLs,
        )
    }

    func importAndComplete(
        session: SyncTransferSession,
        endpoint: SyncEndpoint,
        token: String,
        manifest: SyncManifest,
        playlistSession: SyncPlaylistSession,
        missingEntries: [SyncManifestEntry],
        downloadedURLs: [URL],
    ) async {
        transferPhase = .importing(
            sourceDeviceName: manifest.deviceName,
            currentTrackCount: 0,
            totalTrackCount: downloadedURLs.count,
        )
        notifyStateChanged()

        let importResult = await session.importDownloadedFiles(
            downloadedURLs,
            progress: { [weak self] current, total in
                guard let self else { return }
                transferPhase = .importing(
                    sourceDeviceName: manifest.deviceName,
                    currentTrackCount: current,
                    totalTrackCount: total,
                )
                notifyStateChanged()
            },
        )

        let summary = SyncReceiveSummary(
            offeredCount: manifest.entries.count,
            requestedCount: missingEntries.count,
            downloadedCount: downloadedURLs.count,
            importResult: importResult,
        )
        AppLog.info(
            self,
            "importAndComplete done succeeded=\(importResult.succeeded) duplicates=\(importResult.duplicates) errors=\(importResult.errors) noMetadata=\(importResult.noMetadata) skipped=\(summary.skipped) failed=\(summary.failed)",
        )

        session.stopReceiver()
        AppLog.info(self, "importAndComplete saving playlist session id=\(playlistSession.sessionID) playlist='\(sanitizedLogText(playlistSession.playlistName))'")
        let didSaveSession = await context.completeTransferredPlaylistSession(
            from: manifest,
            autoPlay: true,
        )
        guard didSaveSession else {
            let message = context.takePendingSessionAlertMessage()
                ?? SyncTransferError.invalidPlaylistSession.localizedDescription
            AppLog.error(self, "importAndComplete completeSession failed message=\(message)")
            transferPhase = .failed(message)
            syncReceiverAvailability()
            notifyStateChanged()
            return
        }
        AppLog.info(
            self,
            "importAndComplete complete imported=\(summary.imported) skipped=\(summary.skipped) failed=\(summary.failed)",
        )
        transferPhase = .waiting
        notifyStateChanged()
        await session.reportTransferCompletion(
            endpoint: endpoint,
            token: token,
            alreadyInLibraryTrackCount: manifest.entries.count - missingEntries.count,
        )
    }

    func isLikelyDisconnect(failureCount: Int, requestedCount: Int) -> Bool {
        failureCount > 3 && Double(failureCount) / Double(requestedCount) > 0.5
    }

    func receiverHandshakePayload() -> String? {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            let data = try encoder.encode(context.receiverHandshakeInfo)
            let base64 = data.base64EncodedString()
            var components = URLComponents()
            components.scheme = "museamp"
            components.host = "tv"
            components.queryItems = [URLQueryItem(name: "data", value: base64)]
            return components.url?.absoluteString
        } catch {
            AppLog.error(self, "receiverHandshakePayload failed error=\(error)")
            return nil
        }
    }

    func notifyStateChanged() {
        onStateChanged()
    }
}
