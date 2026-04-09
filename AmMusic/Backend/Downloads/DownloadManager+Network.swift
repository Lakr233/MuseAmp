import AmMusicDatabaseKit
import Combine
import Digger
import Foundation

// MARK: - Network Observation

extension DownloadManager {
    func observeNetworkChanges() {
        networkCancellable = networkMonitor.connectionTypePublisher
            .removeDuplicates()
            .sink { [weak self] connectionType in
                self?.handleNetworkChange(connectionType)
            }
    }

    func handleNetworkChange(_ connectionType: NetworkMonitor.ConnectionType) {
        AppLog.info(self, "Network changed to \(connectionType), isPausedAll=\(isPausedAll)")
        switch connectionType {
        case .wifi:
            isPausedForNetwork = false
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
            isPausedForNetwork = true
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
            isPausedForNetwork = true
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
        if connection == .wifi { return false }
        if connection == .none { return true }
        return !cellularAllowedTrackIDs.contains(trackID)
    }
}
