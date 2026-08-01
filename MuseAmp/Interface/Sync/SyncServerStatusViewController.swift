//
//  SyncServerStatusViewController.swift
//  MuseAmp
//
//  Created by @Lakr233 on 2026/04/11.
//

import AlertController
import ConfigurableKit
import MuseAmpDatabaseKit
import SnapKit
import UIKit

final class SyncServerStatusViewController: StackScrollController {
    enum State {
        case preparing(current: Int, total: Int)
        case ready(
            connectionInfo: SyncConnectionInfo,
            songsReady: Int,
            progress: SyncSenderTransferProgress,
        )
        case interrupted(String)
    }

    let environment: AppEnvironment
    let tracks: [AudioTrackRecord]
    let session: SyncTransferSession

    private var state: State
    private var startupTask: Task<Void, Never>?
    private lazy var backgroundInterruptionObserver = SyncBackgroundInterruptionObserver { [weak self] in
        MainActor.assumeIsolated {
            self?.handleBackgroundInterruption()
        }
    }

    init(
        tracks: [AudioTrackRecord],
        environment: AppEnvironment,
    ) {
        self.tracks = tracks
        self.environment = environment
        session = environment.makeSyncTransferSession()
        state = .preparing(current: 0, total: tracks.count)
        super.init(nibName: nil, bundle: nil)
        title = String(localized: "Sending")
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    deinit {
        let session = self.session
        startupTask?.cancel()
        Task {
            await session.stopSender()
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        session.onSenderProgressChanged = { [weak self] progress in
            self?.applySenderProgress(progress)
        }
        backgroundInterruptionObserver.start()
        startSession()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        environment.screenAwakeCoordinator.acquire(.syncSession)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        environment.screenAwakeCoordinator.release(.syncSession)
        if isMovingFromParent {
            startupTask?.cancel()
            startupTask = nil
            Task {
                await session.stopSender()
            }
        }
    }

    override func setupContentViews() {
        super.setupContentViews()

        switch state {
        case let .preparing(current, total):
            addSectionHeader("Preparing")
            addInfoView(
                title: "Status",
                value: String(localized: "Preparing files..."),
                description: String(localized: "Packaging songs, artwork, and metadata before the receiver connects."),
            )
            addInfoView(
                title: "Progress",
                value: "\(current) / \(max(total, 1))",
                description: String(localized: "This counts how many tracks are ready to be shared on your local network."),
            )

        case let .ready(connectionInfo, songsReady, progress):
            addSectionHeader("Server")
            addInfoView(
                title: "Status",
                value: String(localized: "Ready"),
                description: String(localized: "Nearby devices can find this sender right now."),
            )
            addInfoView(
                title: "Service Name",
                value: connectionInfo.serviceName,
                description: String(localized: "The receiver sees this name while browsing for devices."),
            )
            addEndpointView(connectionInfo: connectionInfo)
            addInfoView(
                title: "Password",
                value: connectionInfo.password,
                description: String(localized: "Enter this temporary code on the receiving device to begin the transfer."),
            )

            addSectionHeader("QR Code")
            if let qrImageView = makeQRCodeView(connectionInfo: connectionInfo) {
                stackView.addArrangedSubview(qrImageView)
            }
            stackView.addArrangedSubview(SeparatorView())

            addSectionHeader("Statistics")
            addInfoView(
                title: "Songs Ready",
                value: "\(songsReady)",
                description: String(localized: "Tracks prepared successfully and waiting for download."),
            )
            if !session.preparedSkippedItems.isEmpty {
                addInfoView(
                    title: "Skipped",
                    value: "\(session.preparedSkippedItems.count)",
                    description: String(localized: "These songs could not be read from local storage and were left out."),
                )
            }

            addSenderTransferSection(progress: progress)

            addSectionHeader("Actions")
            if !session.preparedSkippedItems.isEmpty {
                stackView.addArrangedSubviewWithMargin(makeViewSkippedObject().createView())
                stackView.addArrangedSubview(SeparatorView())
            }
            stackView.addArrangedSubviewWithMargin(makeStopServerObject().createView())
            stackView.addArrangedSubview(SeparatorView())
            stackView.addArrangedSubviewWithMargin(
                ConfigurableSectionFooterView().with(
                    footer: String(localized: "Keep the app active on both devices. Transfers stop if either app moves to the background."),
                ),
            ) { $0.top /= 2 }

        case let .interrupted(message):
            addSectionHeader("Server")
            addInfoView(
                title: "Status",
                value: String(localized: "Interrupted"),
                description: String(localized: "The sender stopped before the transfer could finish."),
            )
            addInfoView(
                title: "Message",
                value: message,
                description: String(localized: "A little more detail about why sharing was interrupted."),
            )

            addSectionHeader("Actions")
            stackView.addArrangedSubviewWithMargin(makeDoneObject().createView())
            stackView.addArrangedSubview(SeparatorView())
        }
    }
}

private extension SyncServerStatusViewController {
    func startSession() {
        startupTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            do {
                try await session.prepareSender(
                    tracks: tracks,
                    progress: { [weak self] current, total in
                        guard let self else {
                            return
                        }
                        state = .preparing(current: current, total: total)
                        refreshUI()
                    },
                )
                _ = try await session.startSender()
                guard let connectionInfo = session.currentConnectionInfo else {
                    throw SyncTransferError.invalidServerResponse
                }
                state = .ready(
                    connectionInfo: connectionInfo,
                    songsReady: session.preparedSongCount,
                    progress: session.senderProgress ?? .waiting(
                        playlistName: nil,
                        totalTrackCount: session.preparedSongCount,
                    ),
                )
                refreshUI()
                presentSkippedNoticeIfNeeded()
            } catch {
                AppLog.error(self, "startSession failed: \(error.localizedDescription)")
                await session.stopSender()
                presentFailureAndPop(message: error.localizedDescription)
            }
        }
    }

    func presentSkippedNoticeIfNeeded() {
        let skippedItems = session.preparedSkippedItems
        guard !skippedItems.isEmpty else {
            return
        }
        let alert = AlertViewController(
            title: String(localized: "Some Songs Skipped"),
            message: String(
                format: String(localized: "%1$lld of %2$lld songs could not be read and were excluded from this transfer."),
                skippedItems.count,
                skippedItems.count + session.preparedSongCount,
            ),
        ) { [weak self] context in
            context.addAction(title: String(localized: "View Skipped Songs")) {
                context.dispose {
                    self?.presentSkippedSongsList()
                }
            }
            context.addAction(title: String(localized: "OK"), attribute: .accent) {
                context.dispose()
            }
        }
        present(alert, animated: true)
    }

    func presentSkippedSongsList() {
        let listController = SkippedSongsViewController(
            items: session.preparedSkippedItems,
            trackRemovalService: environment.musicLibraryTrackRemovalService,
        )
        let navigationController = UINavigationController(rootViewController: listController)
        navigationController.modalPresentationStyle = .formSheet
        present(navigationController, animated: true)
    }

    func makeViewSkippedObject() -> ConfigurableObject {
        ConfigurableObject(
            icon: "exclamationmark.triangle",
            title: "View Skipped Songs",
            explain: "Songs that could not be read and were left out of this transfer.",
            ephemeralAnnotation: .action { [weak self] _ in
                await MainActor.run { self?.presentSkippedSongsList() }
            },
        )
    }

    func handleBackgroundInterruption() {
        startupTask?.cancel()
        Task {
            await session.stopSender()
        }
        state = .interrupted(String(localized: "Sending was interrupted because the app moved to the background."))
        refreshUI()
    }

    func refreshUI() {
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        setupContentViews()
    }

    func applySenderProgress(_ progress: SyncSenderTransferProgress) {
        guard case let .ready(connectionInfo, songsReady, _) = state else {
            return
        }
        state = .ready(
            connectionInfo: connectionInfo,
            songsReady: songsReady,
            progress: progress,
        )
        refreshUI()
    }

    func addSectionHeader(_ title: String.LocalizationValue) {
        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionHeaderView().with(header: String(localized: title)),
        ) { $0.bottom /= 2 }
        stackView.addArrangedSubview(SeparatorView())
    }

    func addSenderTransferSection(progress: SyncSenderTransferProgress) {
        addSectionHeader("Transfer")

        switch progress.phase {
        case .waitingForReceiver:
            addInfoView(
                title: "Status",
                value: String(localized: "Waiting for Receiver..."),
                description: String(localized: "The sender is ready and waiting for another device to authenticate."),
            )

        case .receiverConnected:
            addInfoView(
                title: "Status",
                value: String(localized: "Receiver Connected"),
                description: String(localized: "The receiving device authenticated successfully and is about to request metadata."),
            )

        case .manifestServed:
            addInfoView(
                title: "Status",
                value: String(localized: "Sending Metadata..."),
                description: String(localized: "The receiving device is loading the transfer manifest and preparing its download queue."),
            )

        case .sendingTrack:
            addInfoView(
                title: "Status",
                value: String(localized: "Sending Songs..."),
                description: String(localized: "The receiving device is actively downloading prepared songs from this sender."),
            )
            addInfoView(
                title: "Progress",
                value: "\(progress.currentTrackCount) / \(max(progress.totalTrackCount, 1))",
                description: String(localized: "Prepared tracks served to the receiving device so far."),
            )
            if let currentTrackTitle = progress.currentTrackTitle {
                addInfoView(
                    title: "Current",
                    value: currentTrackTitle,
                    description: String(localized: "The song file currently being transferred."),
                )
            }

        case .completed:
            addInfoView(
                title: "Status",
                value: String(localized: "Sender Complete"),
                description: String(localized: "All prepared tracks were served successfully to the receiving device."),
            )
            addInfoView(
                title: "Progress",
                value: "\(progress.currentTrackCount) / \(max(progress.totalTrackCount, 1))",
                description: String(localized: "Prepared tracks delivered from this sender."),
            )
        }

        if let receiverDeviceName = progress.receiverDeviceName {
            addInfoView(
                title: "Receiver",
                value: receiverDeviceName,
                description: String(localized: "The device currently pulling this transfer."),
            )
        }
    }

    func addInfoView(
        title: String.LocalizationValue,
        value: String,
        description: String? = nil,
        menuBuilder: (() -> [UIMenuElement])? = nil,
    ) {
        let view = ConfigurableInfoView()
        view.configure(icon: UIImage(systemName: "info.circle"))
        view.configure(title: String(localized: title))
        if let description {
            view.configure(description: description)
        }
        view.configure(value: value)
        if let menuBuilder {
            view.use(menu: menuBuilder)
        }
        stackView.addArrangedSubviewWithMargin(view)
        stackView.addArrangedSubview(SeparatorView())
    }

    func addEndpointView(connectionInfo: SyncConnectionInfo) {
        let primaryValue = connectionInfo.fallbackEndpoints.first?.displayString
            ?? String(localized: "No Endpoint")
        addInfoView(
            title: "Primary Endpoint",
            value: primaryValue,
            description: String(localized: "Use one of these addresses if automatic discovery is not available."),
            menuBuilder: {
                connectionInfo.fallbackEndpoints.map { endpoint in
                    UIAction(
                        title: endpoint.displayString,
                        image: UIImage(systemName: "doc.on.doc"),
                    ) { _ in
                        UIPasteboard.general.string = endpoint.displayString
                    }
                }
            },
        )
    }

    func makeQRCodeView(connectionInfo: SyncConnectionInfo) -> UIView? {
        guard let qrImage = makeQRCodeImage(connectionInfo: connectionInfo) else {
            return nil
        }

        let imageView = UIImageView(image: qrImage)
        imageView.contentMode = .scaleAspectFit

        let container = UIView()
        container.addSubview(imageView)
        imageView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.size.equalTo(CGSize(width: 240, height: 240))
        }
        container.snp.makeConstraints { make in
            make.height.equalTo(imageView.snp.height)
        }
        return container
    }

    func makeQRCodeImage(connectionInfo: SyncConnectionInfo) -> UIImage? {
        guard let data = try? JSONEncoder().encode(connectionInfo),
              let filter = CIFilter(name: "CIQRCodeGenerator")
        else {
            return nil
        }

        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let outputImage = filter.outputImage else {
            return nil
        }

        let transform = CGAffineTransform(scaleX: 8, y: 8)
        return UIImage(ciImage: outputImage.transformed(by: transform))
    }

    func makeStopServerObject() -> ConfigurableObject {
        ConfigurableObject(
            icon: "stop.circle",
            title: "Stop Server",
            explain: "Stop sharing songs with other devices.",
            ephemeralAnnotation: .action { [weak self] _ in
                guard let self else {
                    return
                }
                Task { @MainActor [weak self] in
                    guard let self else {
                        return
                    }
                    await session.stopSender()
                    navigationController?.popViewController(animated: true)
                }
            },
        )
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

    func presentFailureAndPop(message: String) {
        let alert = AlertViewController(
            title: String(localized: "Transfer Failed"),
            message: message,
        ) { [weak self] context in
            context.addAction(title: String(localized: "OK"), attribute: .accent) {
                context.dispose {
                    self?.navigationController?.popViewController(animated: true)
                }
            }
        }
        present(alert, animated: true)
    }
}
