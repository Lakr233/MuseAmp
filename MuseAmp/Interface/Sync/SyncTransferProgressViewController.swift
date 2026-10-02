//
//  SyncTransferProgressViewController.swift
//  MuseAmp
//
//  Created by @Lakr233 on 2026/04/11.
//

import AlertController
import ConfigurableKit
import UIKit

final class SyncTransferProgressViewController: StackScrollController {
    enum Phase {
        case fetchingManifest
        case comparing(totalSongs: Int, missingSongs: Int)
        case downloading(current: Int, total: Int, title: String)
        case importing(current: Int, total: Int)
        case complete(imported: Int, skipped: Int, failed: Int)
        case interrupted(String)
    }

    let session: SyncTransferSession
    let endpoint: SyncEndpoint
    let token: String
    let screenAwakeCoordinator: ScreenAwakeCoordinator

    private var phase: Phase = .fetchingManifest
    private var transferTask: Task<Void, Never>?
    private lazy var backgroundInterruptionObserver = SyncBackgroundInterruptionObserver { [weak self] in
        MainActor.assumeIsolated {
            self?.handleBackgroundInterruption()
        }
    }

    private var lastProgressRefreshDate: Date = .distantPast

    init(
        session: SyncTransferSession,
        endpoint: SyncEndpoint,
        token: String,
        screenAwakeCoordinator: ScreenAwakeCoordinator,
    ) {
        self.session = session
        self.endpoint = endpoint
        self.token = token
        self.screenAwakeCoordinator = screenAwakeCoordinator
        super.init(nibName: nil, bundle: nil)
        title = String(localized: "Transferring")
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    deinit {
        let session = self.session
        transferTask?.cancel()
        Task { @MainActor in
            session.stopReceiver()
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        backgroundInterruptionObserver.start()
        startTransfer()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        screenAwakeCoordinator.acquire(.syncSession, owner: self)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        screenAwakeCoordinator.release(.syncSession, owner: self)
        // Leaving stops the transfer; whatever finished downloading is still
        // imported before this controller (and its session) goes away.
        if isLeavingNavigationStack {
            transferTask?.cancel()
        }
    }

    override func setupContentViews() {
        super.setupContentViews()

        switch phase {
        case .fetchingManifest:
            addSectionHeader("Transfer")
            addInfoView(
                title: "Status",
                value: "Fetching song list...",
                description: String(localized: "Asking the sender for the current transfer manifest and song metadata."),
            )

        case let .comparing(totalSongs, missingSongs):
            addSectionHeader("Transfer")
            addInfoView(
                title: "Status",
                value: "Comparing library...",
                description: String(localized: "Checking which songs you already have so duplicates can be skipped."),
            )
            addInfoView(
                title: "Total Songs",
                rawValue: "\(totalSongs)",
                description: String(localized: "The total number of tracks offered by the sender."),
            )
            addInfoView(
                title: "Missing",
                rawValue: "\(missingSongs)",
                description: String(localized: "Only these songs still need to be downloaded on this device."),
            )

        case let .downloading(current, total, title):
            addSectionHeader("Transfer")
            addInfoView(
                title: "Status",
                value: "Downloading...",
                description: String(localized: "Receiving audio files from the sender over your local network."),
            )
            addInfoView(
                title: "Progress",
                rawValue: "\(current) / \(max(total, 1))",
                description: String(localized: "Downloaded songs out of the full transfer queue."),
            )
            addInfoView(
                title: "Current",
                rawValue: title,
                description: String(localized: "The track that is currently being downloaded right now."),
            )

        case let .importing(current, total):
            addSectionHeader("Transfer")
            addInfoView(
                title: "Status",
                value: "Importing...",
                description: String(localized: "Writing finished downloads into your local library database."),
            )
            addInfoView(
                title: "Progress",
                rawValue: "\(current) / \(max(total, 1))",
                description: String(localized: "Imported songs out of the downloaded files that were received."),
            )

        case let .complete(imported, skipped, failed):
            addSectionHeader("Transfer")
            addInfoView(
                title: "Status",
                value: "Complete",
                description: String(localized: "The transfer finished and the results are summarized below."),
            )
            addInfoView(
                title: "Imported",
                rawValue: "\(imported)",
                description: String(localized: "Songs that were added to your library successfully."),
            )
            addInfoView(
                title: "Skipped",
                rawValue: "\(skipped) \(String(localized: "already existed"))",
                description: String(localized: "These tracks were already in your library, so they were left untouched."),
            )
            addInfoView(
                title: "Failed",
                rawValue: "\(failed)",
                description: String(localized: "Files that could not be downloaded or imported cleanly."),
            )

            addSectionHeader("Actions")
            stackView.addArrangedSubviewWithMargin(makeDoneObject().createView())
            stackView.addArrangedSubview(SeparatorView())

        case let .interrupted(message):
            addSectionHeader("Transfer")
            addInfoView(
                title: "Status",
                value: "Interrupted",
                description: String(localized: "The transfer stopped early, but any finished work was preserved."),
            )
            addInfoView(
                title: "Message",
                rawValue: message,
                description: String(localized: "A few extra details about what interrupted the transfer."),
            )

            addSectionHeader("Actions")
            stackView.addArrangedSubviewWithMargin(makeDoneObject().createView())
            stackView.addArrangedSubview(SeparatorView())
        }
    }
}

private extension SyncTransferProgressViewController {
    func startTransfer() {
        transferTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            var offeredCount = 0
            var missingEntries: [SyncManifestEntry] = []
            var downloadedURLs: [URL] = []
            do {
                phase = .fetchingManifest
                refreshUI()

                AppLog.info(self, "startTransfer fetchManifest endpoint=\(endpoint.displayString)")
                let manifest = try await session.fetchManifest(
                    endpoint: endpoint,
                    token: token,
                )
                AppLog.info(self, "startTransfer manifest entries=\(manifest.entries.count) session=\(manifest.session != nil)")
                offeredCount = manifest.entries.count
                missingEntries = await session.missingEntries(in: manifest)

                phase = .comparing(
                    totalSongs: manifest.entries.count,
                    missingSongs: missingEntries.count,
                )
                refreshUI()

                guard !missingEntries.isEmpty else {
                    AppLog.info(self, "startTransfer allTracksExist, nothing to import")
                    session.stopReceiver()
                    presentAlertAndPop(
                        title: String(localized: "Nothing to Import"),
                        message: String(localized: "All songs are already in your library."),
                    )
                    await session.reportTransferCompletion(
                        endpoint: endpoint,
                        token: token,
                        alreadyInLibraryTrackCount: offeredCount,
                    )
                    return
                }

                downloadedURLs = try await session.downloadEntries(
                    endpoint: endpoint,
                    token: token,
                    entries: missingEntries,
                    progress: { [weak self] current, total, entry, _ in
                        guard let self else {
                            return
                        }
                        phase = .downloading(
                            current: current,
                            total: total,
                            title: "\(entry.artistName) - \(entry.title)",
                        )
                        maybeRefreshProgressUI(force: false)
                    },
                )
                AppLog.info(self, "startTransfer downloadPhase done downloaded=\(downloadedURLs.count)/\(missingEntries.count)")

                phase = .importing(current: 0, total: downloadedURLs.count)
                refreshUI()

                let importResult = await session.importDownloadedFiles(
                    downloadedURLs,
                    progress: { [weak self] current, total in
                        guard let self else {
                            return
                        }
                        phase = .importing(current: current, total: total)
                        refreshUI()
                    },
                )
                let summary = SyncReceiveSummary(
                    offeredCount: offeredCount,
                    requestedCount: missingEntries.count,
                    downloadedCount: downloadedURLs.count,
                    importResult: importResult,
                )
                AppLog.info(
                    self,
                    "startTransfer complete imported=\(importResult.succeeded) duplicates=\(importResult.duplicates) errors=\(importResult.errors) noMetadata=\(importResult.noMetadata) alreadyInLibrary=\(offeredCount - missingEntries.count) skipped=\(summary.skipped) failed=\(summary.failed)",
                )

                session.stopReceiver()
                phase = .complete(
                    imported: summary.imported,
                    skipped: summary.skipped,
                    failed: summary.failed,
                )
                refreshUI()
                await session.reportTransferCompletion(
                    endpoint: endpoint,
                    token: token,
                    alreadyInLibraryTrackCount: offeredCount - missingEntries.count,
                )
            } catch let error as SyncTransferSession.PartialDownloadError {
                AppLog.warning(self, "startTransfer partialDownload urls=\(error.downloadedURLs.count)")
                await finishInterruptedTransfer(
                    downloadedURLs: error.downloadedURLs,
                    offeredCount: offeredCount,
                    expectedEntries: missingEntries.count,
                    message: String(localized: "Transfer was interrupted. Imported the files that finished downloading."),
                )
            } catch is CancellationError {
                AppLog.warning(self, "startTransfer cancelled downloaded=\(downloadedURLs.count)")
                await finishInterruptedTransfer(
                    downloadedURLs: downloadedURLs,
                    offeredCount: offeredCount,
                    expectedEntries: missingEntries.count,
                    message: String(localized: "Transfer was interrupted. Imported the files that finished downloading."),
                )
            } catch {
                AppLog.error(self, "startTransfer failed: \(error.localizedDescription)")
                await finishInterruptedTransfer(
                    downloadedURLs: downloadedURLs,
                    offeredCount: offeredCount,
                    expectedEntries: missingEntries.count,
                    message: error.localizedDescription,
                )
            }
        }
    }

    func handleBackgroundInterruption() {
        transferTask?.cancel()
    }

    func maybeRefreshProgressUI(force: Bool) {
        let now = Date()
        guard force || now.timeIntervalSince(lastProgressRefreshDate) > 0.1 else {
            return
        }
        lastProgressRefreshDate = now
        refreshUI()
    }

    func refreshUI() {
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        setupContentViews()
    }

    func addSectionHeader(_ title: String.LocalizationValue) {
        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionHeaderView().with(header: String(localized: title)),
        ) { $0.bottom /= 2 }
        stackView.addArrangedSubview(SeparatorView())
    }

    func addInfoView(
        title: String.LocalizationValue,
        value: String.LocalizationValue,
        description: String? = nil,
    ) {
        addInfoView(
            title: title,
            rawValue: String(localized: value),
            description: description,
        )
    }

    func addInfoView(
        title: String.LocalizationValue,
        rawValue: String,
        description: String? = nil,
    ) {
        let view = ConfigurableInfoView()
        view.configure(icon: UIImage(systemName: "info.circle"))
        view.configure(title: String(localized: title))
        if let description {
            view.configure(description: description)
        }
        view.configure(value: rawValue)
        stackView.addArrangedSubviewWithMargin(view)
        stackView.addArrangedSubview(SeparatorView())
    }

    func makeDoneObject() -> ConfigurableObject {
        ConfigurableObject(
            icon: "checkmark.circle",
            title: "Done",
            explain: "Return to transfer options.",
            ephemeralAnnotation: .action { [weak self] _ in
                await MainActor.run { self?.popToRoleSelection() }
            },
        )
    }

    func presentAlertAndPop(title: String, message: String) {
        let alert = AlertViewController(title: title, message: message) { [weak self] context in
            context.addAction(title: String(localized: "OK"), attribute: .accent) {
                context.dispose {
                    self?.navigationController?.popViewController(animated: true)
                }
            }
        }
        present(alert, animated: true)
    }

    func popToRoleSelection() {
        guard let navigationController else {
            return
        }
        if let target = navigationController.viewControllers.first(where: { $0 is SyncRoleSelectionViewController }) {
            navigationController.popToViewController(target, animated: true)
        } else {
            navigationController.popToRootViewController(animated: true)
        }
    }

    func finishInterruptedTransfer(
        downloadedURLs: [URL],
        offeredCount: Int,
        expectedEntries: Int,
        message: String,
    ) async {
        guard !downloadedURLs.isEmpty else {
            session.stopReceiver()
            phase = .interrupted(message)
            refreshUI()
            return
        }

        phase = .importing(current: 0, total: downloadedURLs.count)
        refreshUI()

        let importResult = await session.importDownloadedFiles(
            downloadedURLs,
            progress: { [weak self] current, total in
                guard let self else {
                    return
                }
                phase = .importing(current: current, total: total)
                refreshUI()
            },
        )

        let summary = SyncReceiveSummary(
            offeredCount: offeredCount,
            requestedCount: expectedEntries,
            downloadedCount: downloadedURLs.count,
            importResult: importResult,
        )
        session.stopReceiver()
        phase = .complete(
            imported: summary.imported,
            skipped: summary.skipped,
            failed: summary.failed,
        )
        refreshUI()
    }
}
