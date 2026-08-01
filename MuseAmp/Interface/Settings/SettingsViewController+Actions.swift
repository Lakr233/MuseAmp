//
//  SettingsViewController+Actions.swift
//  MuseAmp
//
//  Created by @Lakr233 on 2026/04/11.
//

import AlertController
import ConfigurableKit
import Kingfisher
import MuseAmpDatabaseKit
import UIKit

extension SettingsViewController {
    func openPrivacyPolicy() {
        let vc = TextViewerController(
            title: String(localized: "Privacy Policy"),
            text: aboutDocumentText(for: .privacyPolicy),
        )
        navigationController?.pushViewController(vc, animated: true)
    }

    func openOpenSourceLicenses() {
        let vc = TextViewerController(
            title: String(localized: "Open Source Licenses"),
            text: aboutDocumentText(for: .openSourceLicenses),
        )
        navigationController?.pushViewController(vc, animated: true)
    }

    func makePrivacyPolicyObject() -> ConfigurableObject {
        ConfigurableObject(
            icon: "lock.shield",
            title: "Privacy Policy",
            explain: "How Muse Amp handles server settings, local music files, transfers, and on-device data.",
            ephemeralAnnotation: .action { [weak self] _ in
                guard let self else { return }
                openPrivacyPolicy()
            },
        )
    }

    func makeOpenSourceLicensesObject() -> ConfigurableObject {
        ConfigurableObject(
            icon: "flag.filled.and.flag.crossed",
            title: "Open Source Licenses",
            explain: "Third-party libraries and their license terms.",
            ephemeralAnnotation: .action { [weak self] _ in
                guard let self else { return }
                openOpenSourceLicenses()
            },
        )
    }

    func openDownloads() {
        let controller = DownloadsViewController(
            downloadManager: environment.downloadManager,
            playlistStore: environment.playlistStore,
            environment: environment,
        )
        navigationController?.pushViewController(controller, animated: true)
    }

    func openLogs() {
        let controller = LogViewerController()
        navigationController?.pushViewController(controller, animated: true)
    }

    func makeTransferObject() -> ConfigurableObject {
        ConfigurableObject(
            icon: "arrow.triangle.2.circlepath.circle",
            title: "Transfer Songs",
            explain: "Send or receive songs with another device on the same network.",
            ephemeralAnnotation: .action { [weak self] _ in
                self?.openTransfer()
            },
        )
    }

    func openTransfer() {
        let controller = SyncRoleSelectionViewController(environment: environment)
        navigationController?.pushViewController(controller, animated: true)
    }

    @available(iOS 16.0, macCatalyst 17.0, *)
    func makeAppleMusicImportObject() -> ConfigurableObject {
        ConfigurableObject(
            icon: "music.note.house",
            title: "Import from Apple Music",
            explain: "Connect your Apple Music library and import playlists by matching songs against this library.",
            ephemeralAnnotation: .action { [weak self] _ in
                guard let self else { return }
                openAppleMusicImport()
            },
        )
    }

    @available(iOS 16.0, macCatalyst 17.0, *)
    func openAppleMusicImport() {
        let controller = AppleMusicImportViewController(environment: environment)
        navigationController?.pushViewController(controller, animated: true)
    }

    func makeRebuildDatabaseObject() -> ConfigurableObject {
        ConfigurableObject(
            icon: "arrow.triangle.2.circlepath",
            title: "Rebuild Database",
            explain: "Force-rescan all local audio files, re-extract artwork, and repair database mismatches.",
            ephemeralAnnotation: .action { [weak self] _ in
                guard let self else { return }
                confirmRebuildDatabase()
            },
        )
    }

    func confirmRebuildDatabase() {
        ConfirmationAlertPresenter.present(
            on: self,
            title: String(localized: "Rebuild Database"),
            message: String(localized: "This will rescan all local audio files, re-extract artwork, and rebuild the library database. Unreadable files will be removed."),
            confirmTitle: String(localized: "Rebuild"),
        ) { [weak self] in
            self?.rebuildDatabase()
        }
    }

    func makeRebuildAllLyricsIndexObject() -> ConfigurableObject {
        ConfigurableObject(
            icon: "text.quote",
            title: "Rebuild All Lyrics Index",
            explain: "List every song, clear all cached lyrics, fetch lyrics again, and rewrite the lyrics index from scratch.",
            ephemeralAnnotation: .action { [weak self] _ in
                guard let self else { return }
                confirmRebuildAllLyricsIndex()
            },
        )
    }

    func confirmRebuildAllLyricsIndex() {
        ConfirmationAlertPresenter.present(
            on: self,
            title: String(localized: "Rebuild All Lyrics Index"),
            message: String(localized: "This will list every song, delete all cached lyrics, fetch lyrics again, and rewrite the lyrics index from scratch. Existing lyric data will be refreshed for every song."),
            confirmTitle: String(localized: "Rebuild"),
        ) { [weak self] in
            self?.rebuildAllLyricsIndex()
        }
    }

    func rebuildDatabase() {
        let progressAlert = AlertProgressIndicatorViewController(
            title: String(localized: "Rebuilding Database"),
            message: String(localized: "Scanning local files..."),
        )
        present(progressAlert, animated: true)

        Task { @MainActor [weak self, weak progressAlert, env = environment] in
            do {
                ImageCache.default.clearMemoryCache()
                await withCheckedContinuation { continuation in
                    ImageCache.default.clearDiskCache { continuation.resume() }
                }
                Self.removeOldAPICacheDirectory()

                guard let progressAlert else { return }
                let result = try await env.rebuildLibraryDatabase(
                    forceArtwork: true,
                    progressCallback: { current, total in
                        DispatchQueue.main.async {
                            progressAlert.progressContext.purpose(
                                message: String(
                                    format: String(localized: "Processing %d/%d..."),
                                    current + 1, total,
                                ),
                            )
                        }
                    },
                )
                progressAlert.dismiss(animated: true) {
                    guard let self else { return }
                    self.presentRebuildResult(result)
                }
            } catch {
                AppLog.error("SettingsViewController", "rebuildDatabase failed: \(error.localizedDescription)")
                progressAlert?.dismiss(animated: true) {
                    guard let self else { return }
                    let alert = AlertViewController(
                        title: String(localized: "Rebuild Failed"),
                        message: error.localizedDescription,
                    ) { context in
                        context.addAction(title: String(localized: "OK"), attribute: .accent) { context.dispose() }
                    }
                    self.present(alert, animated: true)
                }
            }
        }
    }

    func presentRebuildResult(_ result: SongLibraryIndexer.SyncResult) {
        var message = String(
            format: String(localized: "Scanned %1$lld, updated %2$lld, removed %3$lld."),
            result.filesScanned, result.upserts, result.deletions,
        )
        if !result.removedInvalidFiles.isEmpty {
            message += "\n" + String(
                format: String(localized: "%lld unreadable files were detected and deleted."),
                result.removedInvalidFiles.count,
            )
        }
        let alert = AlertViewController(
            title: String(localized: "Rebuild Complete"),
            message: message,
        ) { [weak self] context in
            if !result.removedInvalidFiles.isEmpty {
                context.addAction(title: String(localized: "View Deleted Files")) {
                    context.dispose {
                        self?.presentRemovedInvalidFiles(result.removedInvalidFiles)
                    }
                }
            }
            context.addAction(title: String(localized: "OK"), attribute: .accent) { context.dispose() }
        }
        present(alert, animated: true)
    }

    func presentRemovedInvalidFiles(_ removedFiles: [RemovedInvalidFile]) {
        let items = removedFiles.map { file in
            PreparedTransferSkippedItem(
                trackID: file.trackID ?? file.relativePath,
                title: file.title ?? URL(fileURLWithPath: file.relativePath).lastPathComponent,
                artistName: file.artistName ?? "",
                reason: file.reason,
            )
        }
        let listController = SkippedSongsViewController(
            items: items,
            trackRemovalService: nil,
            title: String(localized: "Deleted Files"),
        )
        let navigationController = UINavigationController(rootViewController: listController)
        navigationController.modalPresentationStyle = .formSheet
        present(navigationController, animated: true)
    }

    func rebuildAllLyricsIndex() {
        let progressAlert = AlertProgressIndicatorViewController(
            title: String(localized: "Rebuilding Lyrics Index"),
            message: String(localized: "Listing songs and clearing cached lyrics..."),
        )
        present(progressAlert, animated: true)

        Task { @MainActor [weak self, env = environment] in
            do {
                let result = try await env.rebuildAllLyricsIndex(
                    progressCallback: { current, total, trackTitle in
                        DispatchQueue.main.async {
                            progressAlert.progressContext.purpose(
                                message: String(
                                    format: String(localized: "Refreshing %d/%d...\n%@"),
                                    current + 1, total, trackTitle,
                                ),
                            )
                        }
                    },
                )
                progressAlert.dismiss(animated: true) {
                    guard let self else { return }
                    let alert = AlertViewController(
                        title: String(localized: "Lyrics Rebuild Complete"),
                        message: String(
                            format: String(localized: "Processed %d, refreshed %d, failed %d"),
                            result.tracksProcessed, result.tracksSucceeded, result.tracksFailed,
                        ),
                    ) { context in
                        context.addAction(title: String(localized: "OK"), attribute: .accent) { context.dispose() }
                    }
                    self.present(alert, animated: true)
                }
            } catch {
                AppLog.error("SettingsViewController", "rebuildAllLyricsIndex failed: \(error.localizedDescription)")
                progressAlert.dismiss(animated: true) {
                    guard let self else { return }
                    let alert = AlertViewController(
                        title: String(localized: "Lyrics Rebuild Failed"),
                        message: error.localizedDescription,
                    ) { context in
                        context.addAction(title: String(localized: "OK"), attribute: .accent) { context.dispose() }
                    }
                    self.present(alert, animated: true)
                }
            }
        }
    }

    private static func removeOldAPICacheDirectory() {
        guard let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return
        }
        let cacheDir = cachesURL.appendingPathComponent("APIResponseCache", isDirectory: true)
        guard FileManager.default.fileExists(atPath: cacheDir.path) else { return }
        do {
            try FileManager.default.removeItem(at: cacheDir)
            AppLog.info("SettingsViewController", "removed old APIResponseCache directory")
        } catch {
            AppLog.warning("SettingsViewController", "failed to remove APIResponseCache: \(error.localizedDescription)")
        }
    }
}

private extension SettingsViewController {
    enum AboutDocumentSection {
        case privacyPolicy
        case openSourceLicenses

        var resourceName: String {
            switch self {
            case .privacyPolicy:
                "PrivacyPolicy"
            case .openSourceLicenses:
                "OpenSourceLicenses"
            }
        }
    }

    func aboutDocumentText(for section: AboutDocumentSection) -> String {
        let fallback = String(localized: "Resource not found, please check your installation.")
        guard let url = Bundle.main.url(forResource: section.resourceName, withExtension: "md"),
              let content = try? String(contentsOf: url)
        else {
            return fallback
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
