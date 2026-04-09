import AlertController
import ConfigurableKit
import SPIndicator
import UIKit

extension SettingsViewController {
    func openDownloads() {
        let controller = DownloadsViewController(
            downloadManager: environment.downloadManager,
            playlistStore: environment.playlistStore,
            environment: environment
        )
        navigationController?.pushViewController(controller, animated: true)
    }

    func openLogs() {
        let controller = LogViewerController()
        navigationController?.pushViewController(controller, animated: true)
    }

    func confirmClearAPICache() {
        ConfirmationAlertPresenter.present(
            on: self,
            title: String(localized: "Clear API Cache"),
            message: String(localized: "This removes all cached API responses and forces future requests to hit the network again."),
            confirmTitle: String(localized: "Clear")
        ) { [weak self] in
            self?.clearAPICache()
        }
    }

    func clearAPICache() {
        Task { @MainActor in
            await environment.apiClient.clearResponseCache()
            SPIndicator.present(
                title: String(localized: "API Cache Cleared"),
                message: String(localized: "Future API requests will fetch fresh data."),
                preset: .done
            )
        }
    }

    func makeRebuildDatabaseObject() -> ConfigurableObject {
        ConfigurableObject(
            icon: "arrow.triangle.2.circlepath",
            title: "Rebuild Database",
            explain: "Force-rescan all local audio files, re-extract artwork, and repair database mismatches.",
            ephemeralAnnotation: .action { [weak self] _ in
                guard let self else { return }
                confirmRebuildDatabase()
            }
        )
    }

    func confirmRebuildDatabase() {
        ConfirmationAlertPresenter.present(
            on: self,
            title: String(localized: "Rebuild Database"),
            message: String(localized: "This will rescan all local audio files, re-extract artwork, and rebuild the library database. Unreadable files will be removed."),
            confirmTitle: String(localized: "Rebuild")
        ) { [weak self] in
            self?.rebuildDatabase()
        }
    }

    func rebuildDatabase() {
        let progressAlert = AlertProgressIndicatorViewController(
            title: String(localized: "Rebuilding Database"),
            message: String(localized: "Scanning local files...")
        )
        present(progressAlert, animated: true)

        Task { @MainActor [weak self, weak progressAlert, env = environment] in
            do {
                let result = try await env.rebuildLibraryDatabase(
                    forceArtwork: true,
                    progressCallback: { current, total in
                        Task { @MainActor [weak progressAlert] in
                            progressAlert?.progressContext.purpose(
                                message: String(
                                    format: String(localized: "Processing %d/%d..."),
                                    current + 1, total
                                )
                            )
                        }
                    }
                )
                progressAlert?.dismiss(animated: true) {
                    guard let self else { return }
                    let alert = AlertViewController(
                        title: String(localized: "Rebuild Complete"),
                        message: String(
                            format: String(localized: "Scanned %d, updated %d, removed %d, purged %d"),
                            result.filesScanned, result.upserts, result.deletions, result.purged
                        )
                    ) { context in
                        context.addAction(title: String(localized: "OK"), attribute: .accent) { context.dispose() }
                    }
                    self.present(alert, animated: true)
                }
            } catch {
                AppLog.error("SettingsViewController", "rebuildDatabase failed: \(error.localizedDescription)")
                progressAlert?.dismiss(animated: true) {
                    guard let self else { return }
                    let alert = AlertViewController(
                        title: String(localized: "Rebuild Failed"),
                        message: error.localizedDescription
                    ) { context in
                        context.addAction(title: String(localized: "OK"), attribute: .accent) { context.dispose() }
                    }
                    self.present(alert, animated: true)
                }
            }
        }
    }
}
