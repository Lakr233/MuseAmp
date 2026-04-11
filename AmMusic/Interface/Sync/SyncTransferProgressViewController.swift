//
//  SyncTransferProgressViewController.swift
//  AmMusic
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

    private var phase: Phase = .fetchingManifest
    private var transferTask: Task<Void, Never>?
    private lazy var backgroundInterruptionObserver = SyncBackgroundInterruptionObserver { [weak self] in
        self?.handleBackgroundInterruption()
    }

    private var lastProgressRefreshDate: Date = .distantPast

    init(
        session: SyncTransferSession,
        endpoint: SyncEndpoint,
        token: String,
    ) {
        self.session = session
        self.endpoint = endpoint
        self.token = token
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

    override func setupContentViews() {
        super.setupContentViews()

        switch phase {
        case .fetchingManifest:
            addSectionHeader("Transfer")
            addInfoView(title: "Status", value: "Fetching song list...")

        case let .comparing(totalSongs, missingSongs):
            addSectionHeader("Transfer")
            addInfoView(title: "Status", value: "Comparing library...")
            addInfoView(title: "Total Songs", rawValue: "\(totalSongs)")
            addInfoView(title: "Missing", rawValue: "\(missingSongs)")

        case let .downloading(current, total, title):
            addSectionHeader("Transfer")
            addInfoView(title: "Status", value: "Downloading...")
            addInfoView(title: "Progress", rawValue: "\(current) / \(max(total, 1))")
            addInfoView(title: "Current", rawValue: title)

        case let .importing(current, total):
            addSectionHeader("Transfer")
            addInfoView(title: "Status", value: "Importing...")
            addInfoView(title: "Progress", rawValue: "\(current) / \(max(total, 1))")

        case let .complete(imported, skipped, failed):
            addSectionHeader("Transfer")
            addInfoView(title: "Status", value: "Complete")
            addInfoView(title: "Imported", rawValue: "\(imported)")
            addInfoView(title: "Skipped", rawValue: "\(skipped) \(String(localized: "already existed"))")
            addInfoView(title: "Failed", rawValue: "\(failed)")

            addSectionHeader("Actions")
            stackView.addArrangedSubviewWithMargin(makeDoneObject().createView())
            stackView.addArrangedSubview(SeparatorView())

        case let .interrupted(message):
            addSectionHeader("Transfer")
            addInfoView(title: "Status", value: "Interrupted")
            addInfoView(title: "Message", rawValue: message)

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

            do {
                phase = .fetchingManifest
                refreshUI()

                let manifest = try await session.fetchManifest(
                    endpoint: endpoint,
                    token: token,
                )
                let missingEntries = await session.missingEntries(in: manifest)

                phase = .comparing(
                    totalSongs: manifest.entries.count,
                    missingSongs: missingEntries.count,
                )
                refreshUI()

                guard !missingEntries.isEmpty else {
                    session.stopReceiver()
                    presentAlertAndPop(
                        title: String(localized: "Nothing to Import"),
                        message: String(localized: "All songs are already in your library."),
                    )
                    return
                }

                let downloadedURLs = await session.downloadEntries(
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
                let downloadFailures = max(missingEntries.count - downloadedURLs.count, 0)
                let failedCount = importResult.errors + importResult.noMetadata + downloadFailures

                session.stopReceiver()
                phase = .complete(
                    imported: importResult.succeeded,
                    skipped: importResult.duplicates,
                    failed: failedCount,
                )
                refreshUI()
            } catch {
                AppLog.error(self, "startTransfer failed: \(error.localizedDescription)")
                session.stopReceiver()
                presentAlertAndPop(
                    title: String(localized: "Transfer Failed"),
                    message: error.localizedDescription,
                )
            }
        }
    }

    func handleBackgroundInterruption() {
        transferTask?.cancel()
        session.stopReceiver()
        phase = .interrupted(String(localized: "Receiving was interrupted because the app moved to the background."))
        refreshUI()
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

    func addInfoView(title: String.LocalizationValue, value: String.LocalizationValue) {
        addInfoView(title: title, rawValue: String(localized: value))
    }

    func addInfoView(title: String.LocalizationValue, rawValue: String) {
        let view = ConfigurableInfoView()
        view.configure(icon: UIImage(systemName: "info.circle"))
        view.configure(title: String(localized: title))
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
        let alert = AlertViewController(title: title, message: message) { context in
            context.addAction(title: String(localized: "OK"), attribute: .accent) {
                context.dispose { [weak self] in
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
}
