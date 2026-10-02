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
        case connecting(deviceName: String)
        case receiving(
            sourceDeviceName: String,
            playlistName: String,
            receivedTrackCount: Int,
            totalTrackCount: Int,
            currentTrackTitle: String?,
            progress: Double,
        )
        case importing(sourceDeviceName: String, playlistName: String, currentTrackCount: Int, totalTrackCount: Int)
        case completed(
            sourceDeviceName: String,
            playlistName: String,
            importedTrackCount: Int,
            skippedTrackCount: Int,
            failedTrackCount: Int,
        )
        case disconnected(
            sourceDeviceName: String,
            playlistName: String,
            endpoint: SyncEndpoint,
            token: String,
            manifest: SyncManifest,
            completedEntryTrackIDs: Set<String>,
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
        startReceiverAvailability()
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
        startReceiverAvailability()
        notifyStateChanged()
    }

    func retryTransfer() {
        guard case let .disconnected(
            sourceDeviceName, _, endpoint, token, manifest, completedIDs, previousURLs,
        ) = transferPhase else { return }

        transferTask?.cancel()
        transferTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await resumeTransfer(
                sourceDeviceName: sourceDeviceName,
                endpoint: endpoint,
                token: token,
                manifest: manifest,
                completedEntryTrackIDs: completedIDs,
                previousDownloadedURLs: previousURLs,
            )
        }
    }

    func syncReceiverAvailability() {
        startReceiverAvailability()
    }

    var sessionState: AMTVLibrarySessionState {
        let trackCount = context.currentSessionTrackCount
        let snapshot = context.playbackController.snapshot

        if snapshot.currentTrack != nil {
            return .playing(trackCount: max(trackCount, snapshot.queue.count))
        }

        switch transferPhase {
        case let .receiving(_, _, receivedTrackCount, totalTrackCount, _, _):
            return .receivingTracks(count: receivedTrackCount, totalCount: totalTrackCount)
        case let .importing(_, _, currentTrackCount, totalTrackCount):
            return .receivingTracks(count: currentTrackCount, totalCount: totalTrackCount)
        case let .failed(message):
            if trackCount == 0 {
                return .failed(message: message)
            }
        case let .disconnected(_, playlistName, _, _, _, _, _):
            if trackCount == 0 {
                return .failed(message: String(localized: "Connection lost while receiving \"\(playlistName)\"."))
            }
        case .waiting, .connecting, .completed:
            break
        }

        if trackCount > 0 {
            return .playing(trackCount: trackCount)
        }
        return .awaitingUpload
    }

    var uploadWaitingContent: AMTVUploadWaitingContent {
        if case let .connecting(deviceName) = transferPhase {
            return AMTVUploadWaitingContent(
                title: String(localized: "Connecting to Sender"),
                message: String(localized: "Authenticating with the selected iPhone sender and preparing the transfer manifest for this Apple TV session."),
                deviceName: context.receiverHandshakeInfo.deviceName,
                connectionCodeTitle: String(localized: "Selected Sender"),
                connectionCode: deviceName,
                qrPayload: receiverHandshakePayload(),
            )
        }

        return AMTVUploadWaitingContent(
            title: String(localized: "Awaiting Upload"),
            message: String(localized: "On an iPhone with Muse Amp installed, use the system camera to scan the QR code displayed on this Apple TV, then select the songs to transfer."),
            deviceName: context.receiverHandshakeInfo.deviceName,
            connectionCodeTitle: nil,
            connectionCode: nil,
            qrPayload: receiverHandshakePayload(),
        )
    }

    var receivingTracksContent: AMTVReceivingTracksContent? {
        switch transferPhase {
        case let .receiving(sourceDeviceName, playlistName, receivedTrackCount, totalTrackCount, currentTrackTitle, progress):
            return AMTVReceivingTracksContent(
                title: String(localized: "Receiving Playlist \"\(playlistName)\""),
                sourceDeviceName: sourceDeviceName,
                receivedTrackCount: receivedTrackCount,
                totalTrackCount: totalTrackCount,
                currentTrackTitle: currentTrackTitle,
                progress: progress,
            )
        case let .importing(sourceDeviceName, playlistName, currentTrackCount, totalTrackCount):
            let progress = totalTrackCount > 0 ? Double(currentTrackCount) / Double(totalTrackCount) : 1
            return AMTVReceivingTracksContent(
                title: String(localized: "Finishing Playlist \"\(playlistName)\""),
                sourceDeviceName: sourceDeviceName,
                receivedTrackCount: currentTrackCount,
                totalTrackCount: totalTrackCount,
                currentTrackTitle: String(localized: "Saving playlist session"),
                progress: progress,
            )
        case .waiting, .connecting, .completed, .disconnected, .failed:
            return nil
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

    func connect(endpoint: SyncEndpoint, password: String) {
        transferTask?.cancel()
        transferTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            await runTransfer(
                sourceDeviceName: endpoint.displayString,
                endpoints: [endpoint],
                password: password,
            )
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
            startReceiverAvailability()
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
            startReceiverAvailability()
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
        transferPhase = .connecting(deviceName: sourceDeviceName)
        receiverAdvertiser.stop()
        notifyStateChanged()

        let session = context.syncTransferSession
        guard !endpoints.isEmpty else {
            transferPhase = .failed(
                SyncTransferError.noResolvableEndpoint.errorDescription
                    ?? String(localized: "No reachable sender was available."),
            )
            notifyStateChanged()
            return
        }

        var lastErrorMessage = SyncTransferError.noResolvableEndpoint.errorDescription
            ?? String(localized: "No reachable sender was available.")

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
        startReceiverAvailability()
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
                    ?? SyncTransferError.invalidPlaylistSession.errorDescription
                    ?? String(localized: "The transferred playlist could not be saved.")
                AppLog.error(self, "receiveTransfer completeSession failed (no missing) message=\(message)")
                transferPhase = .failed(message)
                startReceiverAvailability()
                notifyStateChanged()
                return
            }
            transferPhase = .completed(
                sourceDeviceName: manifest.deviceName,
                playlistName: playlistSession.playlistName,
                importedTrackCount: 0,
                skippedTrackCount: manifest.entries.count,
                failedTrackCount: 0,
            )
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
            playlistName: playlistSession.playlistName,
            receivedTrackCount: 0,
            totalTrackCount: missingEntries.count,
            currentTrackTitle: nil,
            progress: 0,
        )
        notifyStateChanged()

        let downloadedURLs: [URL]
        do {
            downloadedURLs = try await session.downloadEntries(
                endpoint: endpoint,
                token: token,
                entries: missingEntries,
                progress: { [weak self] current, total, entry, fractionCompleted in
                    guard let self else {
                        return
                    }
                    let completed = max(current - 1, 0)
                    let progress = total > 0
                        ? (Double(completed) + fractionCompleted) / Double(total)
                        : fractionCompleted
                    transferPhase = .receiving(
                        sourceDeviceName: manifest.deviceName,
                        playlistName: playlistSession.playlistName,
                        receivedTrackCount: current,
                        totalTrackCount: total,
                        currentTrackTitle: String(localized: "\(entry.artistName) - \(entry.title)"),
                        progress: progress,
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
        if downloadFailureCount > 3,
           missingEntries.count > 0,
           Double(downloadFailureCount) / Double(missingEntries.count) > 0.5
        {
            let completedIDs = Set(downloadedURLs.compactMap { url -> String? in
                url.deletingPathExtension().lastPathComponent
            })
            AppLog.warning(
                self,
                "receiveTransfer disconnect detected failures=\(downloadFailureCount)/\(missingEntries.count), offering retry",
            )
            transferPhase = .disconnected(
                sourceDeviceName: manifest.deviceName,
                playlistName: playlistSession.playlistName,
                endpoint: endpoint,
                token: token,
                manifest: manifest,
                completedEntryTrackIDs: completedIDs,
                downloadedURLs: downloadedURLs,
            )
            notifyStateChanged()
            return
        }

        transferPhase = .importing(
            sourceDeviceName: manifest.deviceName,
            playlistName: playlistSession.playlistName,
            currentTrackCount: 0,
            totalTrackCount: downloadedURLs.count,
        )
        notifyStateChanged()

        let importResult = await session.importDownloadedFiles(
            downloadedURLs,
            progress: { [weak self] current, total in
                guard let self else {
                    return
                }
                transferPhase = .importing(
                    sourceDeviceName: manifest.deviceName,
                    playlistName: playlistSession.playlistName,
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
            "receiveTransfer importDone succeeded=\(importResult.succeeded) duplicates=\(importResult.duplicates) errors=\(importResult.errors) noMetadata=\(importResult.noMetadata) skipped=\(summary.skipped) failed=\(summary.failed)",
        )

        session.stopReceiver()
        AppLog.info(self, "receiveTransfer saving playlist session id=\(playlistSession.sessionID) playlist='\(sanitizedLogText(playlistSession.playlistName))'")
        let didSaveSession = await context.completeTransferredPlaylistSession(
            from: manifest,
            autoPlay: true,
        )
        guard didSaveSession else {
            let message = context.takePendingSessionAlertMessage()
                ?? SyncTransferError.invalidPlaylistSession.errorDescription
                ?? String(localized: "The transferred playlist could not be saved.")
            AppLog.error(self, "receiveTransfer completeSession failed message=\(message)")
            transferPhase = .failed(message)
            startReceiverAvailability()
            notifyStateChanged()
            return
        }
        AppLog.info(
            self,
            "receiveTransfer complete imported=\(summary.imported) skipped=\(summary.skipped) failed=\(summary.failed)",
        )
        transferPhase = .completed(
            sourceDeviceName: manifest.deviceName,
            playlistName: playlistSession.playlistName,
            importedTrackCount: summary.imported,
            skippedTrackCount: summary.skipped,
            failedTrackCount: summary.failed,
        )
        notifyStateChanged()
        await session.reportTransferCompletion(
            endpoint: endpoint,
            token: token,
            alreadyInLibraryTrackCount: manifest.entries.count - missingEntries.count,
        )
    }

    func resumeTransfer(
        sourceDeviceName: String,
        endpoint: SyncEndpoint,
        token: String,
        manifest: SyncManifest,
        completedEntryTrackIDs: Set<String>,
        previousDownloadedURLs: [URL],
    ) async {
        guard let playlistSession = manifest.session else {
            transferPhase = .failed(
                SyncTransferError.invalidPlaylistSession.errorDescription
                    ?? String(localized: "The transferred playlist could not be saved."),
            )
            notifyStateChanged()
            return
        }

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
            sourceDeviceName: sourceDeviceName,
            playlistName: playlistSession.playlistName,
            receivedTrackCount: alreadyDownloaded,
            totalTrackCount: missingEntries.count,
            currentTrackTitle: String(localized: "Resuming transfer..."),
            progress: Double(alreadyDownloaded) / Double(missingEntries.count),
        )
        notifyStateChanged()

        let newDownloadedURLs: [URL]
        do {
            newDownloadedURLs = try await session.downloadEntries(
                endpoint: endpoint,
                token: token,
                entries: remainingEntries,
                progress: { [weak self] current, _, entry, fractionCompleted in
                    guard let self else { return }
                    let adjustedCurrent = alreadyDownloaded + current
                    let adjustedTotal = missingEntries.count
                    let completed = max(adjustedCurrent - 1, 0)
                    let progress = adjustedTotal > 0
                        ? (Double(completed) + fractionCompleted) / Double(adjustedTotal)
                        : fractionCompleted
                    transferPhase = .receiving(
                        sourceDeviceName: sourceDeviceName,
                        playlistName: playlistSession.playlistName,
                        receivedTrackCount: adjustedCurrent,
                        totalTrackCount: adjustedTotal,
                        currentTrackTitle: String(localized: "\(entry.artistName) - \(entry.title)"),
                        progress: progress,
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
        if resumeFailureCount > 3,
           remainingEntries.count > 0,
           Double(resumeFailureCount) / Double(remainingEntries.count) > 0.5
        {
            let allCompletedIDs = completedEntryTrackIDs.union(
                newDownloadedURLs.compactMap { $0.deletingPathExtension().lastPathComponent },
            )
            AppLog.warning(self, "resumeTransfer disconnect again failures=\(resumeFailureCount)/\(remainingEntries.count)")
            transferPhase = .disconnected(
                sourceDeviceName: sourceDeviceName,
                playlistName: playlistSession.playlistName,
                endpoint: endpoint,
                token: token,
                manifest: manifest,
                completedEntryTrackIDs: allCompletedIDs,
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
            playlistName: playlistSession.playlistName,
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
                    playlistName: playlistSession.playlistName,
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
        let didSaveSession = await context.completeTransferredPlaylistSession(
            from: manifest,
            autoPlay: true,
        )
        guard didSaveSession else {
            let message = context.takePendingSessionAlertMessage()
                ?? SyncTransferError.invalidPlaylistSession.errorDescription
                ?? String(localized: "The transferred playlist could not be saved.")
            AppLog.error(self, "importAndComplete completeSession failed message=\(message)")
            transferPhase = .failed(message)
            startReceiverAvailability()
            notifyStateChanged()
            return
        }
        AppLog.info(
            self,
            "importAndComplete complete imported=\(summary.imported) skipped=\(summary.skipped) failed=\(summary.failed)",
        )
        transferPhase = .completed(
            sourceDeviceName: manifest.deviceName,
            playlistName: playlistSession.playlistName,
            importedTrackCount: summary.imported,
            skippedTrackCount: summary.skipped,
            failedTrackCount: summary.failed,
        )
        notifyStateChanged()
        await session.reportTransferCompletion(
            endpoint: endpoint,
            token: token,
            alreadyInLibraryTrackCount: manifest.entries.count - missingEntries.count,
        )
    }

    func startReceiverAvailability() {
        let shouldAdvertiseReceiver: Bool = switch transferPhase {
        case .connecting, .receiving, .importing, .disconnected:
            false
        case .waiting, .completed, .failed:
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
