//
//  DownloadManager+Network.swift
//  MuseAmp
//
//  Created by @Lakr233 on 2026/04/11.
//

import Combine
import ConfigurableKit
import Digger
import Foundation
import MuseAmpDatabaseKit

// MARK: - Network Observation

extension DownloadManager {
    func observeConcurrencyChanges() {
        ConfigurableKit.publisher(forKey: AppPreferences.maxConcurrentDownloadsKey, type: Int.self)
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self else { return }
                // Digger rebuilds its URLSession when the limit is assigned,
                // cancelling every in-flight download. Our own queue gating
                // picks up the new limit immediately; Digger's session limit is
                // synced later when no download is active.
                AppLog.info(self, "Max concurrent downloads changed to \(maxConcurrent)")
                syncDiggerConcurrencyIfNeeded()
                processNextIfNeeded()
            }
            .store(in: &cancellables)
    }

    func observeNetworkChanges() {
        networkMonitor.connectionTypePublisher
            .removeDuplicates()
            .sink { [weak self] connectionType in
                self?.handleNetworkChange(connectionType)
            }
            .store(in: &cancellables)
    }

    func handleNetworkChange(_ connectionType: NetworkMonitor.ConnectionType) {
        AppLog.info(self, "Network changed to \(connectionType), isPausedAll=\(isPausedAll)")
        switch connectionType {
        case .wifi:
            guard !isPausedAll else { return }
            var resumedCount = 0
            for key in tasks.keys {
                if tasks[key]?.state == .waitingForNetwork {
                    tasks[key]?.state = .waiting
                    persistRecord(trackID: key, state: .queued)
                    resumedCount += 1
                }
            }
            AppLog.info(self, "WiFi available: resumed \(resumedCount) network-waiting tasks")
            publishSnapshot()
            processNextIfNeeded()

        case .cellular:
            guard !isPausedAll else { return }
            var deferredCount = 0
            for key in tasks.keys {
                guard tasks[key]?.state == .downloading,
                      !cellularAllowedTrackIDs.contains(key),
                      let url = tasks[key]?.url
                else { continue }
                intentionallyPaused.insert(key)
                DiggerManager.shared.stopTask(for: url)
                tasks[key]?.state = .waitingForNetwork
                tasks[key]?.speed = 0
                persistRecord(trackID: key, state: .waitingForNetwork)
                deferredCount += 1
            }
            updateDeferredStatesForPendingTasks()
            AppLog.info(self, "Cellular active: deferred \(deferredCount) downloading tasks")
            publishSnapshot()

        case .none:
            guard !isPausedAll else { return }
            var deferredCount = 0
            for key in tasks.keys where tasks[key]?.state == .downloading {
                if let url = tasks[key]?.url {
                    intentionallyPaused.insert(key)
                    DiggerManager.shared.stopTask(for: url)
                }
                tasks[key]?.state = .waitingForNetwork
                tasks[key]?.speed = 0
                persistRecord(trackID: key, state: .waitingForNetwork)
                deferredCount += 1
            }
            updateDeferredStatesForPendingTasks()
            AppLog.info(self, "No connection: deferred \(deferredCount) downloading tasks")
            publishSnapshot()
        }
    }

    func shouldDeferForNetwork(trackID: String) -> Bool {
        let connection = networkMonitor.connectionType
        if connection == .wifi {
            return false
        }
        if connection == .none {
            return true
        }
        return !cellularAllowedTrackIDs.contains(trackID)
    }
}
