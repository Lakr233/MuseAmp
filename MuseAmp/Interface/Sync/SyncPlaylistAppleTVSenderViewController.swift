//
//  SyncPlaylistAppleTVSenderViewController.swift
//  MuseAmp
//
//  Created by OpenAI on 2026/04/12.
//

import AlertController
import AVFoundation
import ConfigurableKit
import MuseAmpDatabaseKit
import SnapKit
import UIKit

final class SyncPlaylistAppleTVSenderViewController: StackScrollController {
    private enum State {
        case preparing(current: Int, total: Int)
        case ready(
            connectionInfo: SyncConnectionInfo,
            plan: SyncPlaylistTransferPlan,
            progress: SyncSenderTransferProgress,
        )
        case interrupted(String)
    }

    private let playlistID: UUID?
    private let initialTracks: [AudioTrackRecord]?
    private let environment: AppEnvironment
    private let session: SyncTransferSession
    private let receiverBrowser = SyncBonjourBrowser(allowedRoles: [.receiver])

    private var state: State
    private var startupTask: Task<Void, Never>?
    private var selectedReceiverInfo: SyncReceiverHandshakeInfo?

    private lazy var backgroundInterruptionObserver = SyncBackgroundInterruptionObserver { [weak self] in
        MainActor.assumeIsolated {
            self?.handleBackgroundInterruption()
        }
    }

    init(playlistID: UUID, environment: AppEnvironment) {
        self.playlistID = playlistID
        initialTracks = nil
        self.environment = environment
        session = environment.makeSyncTransferSession()
        state = .preparing(current: 0, total: 1)
        super.init(nibName: nil, bundle: nil)
        title = String(localized: "Send to Apple TV")
    }

    init(
        tracks: [AudioTrackRecord],
        receiverInfo: SyncReceiverHandshakeInfo,
        environment: AppEnvironment,
    ) {
        playlistID = nil
        initialTracks = tracks
        self.environment = environment
        session = environment.makeSyncTransferSession()
        selectedReceiverInfo = receiverInfo
        state = .preparing(current: 0, total: 1)
        super.init(nibName: nil, bundle: nil)
        title = String(localized: "Send to Apple TV")
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    deinit {
        let session = self.session
        let receiverBrowser = self.receiverBrowser
        startupTask?.cancel()
        Task { @MainActor in
            receiverBrowser.stop()
            await session.stopSender()
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let doneButton = UIBarButtonItem(
            image: UIImage(systemName: "checkmark"),
            style: .done,
            target: self,
            action: #selector(dismissFormSheet),
        )
        doneButton.tintColor = .accent
        navigationItem.rightBarButtonItem = doneButton
        receiverBrowser.onDevicesChanged = { [weak self] _ in
            self?.refreshUI()
        }
        session.onSenderProgressChanged = { [weak self] progress in
            self?.applySenderProgress(progress)
        }
        receiverBrowser.start()
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
            receiverBrowser.stop()
            Task {
                await session.stopSender()
            }
        }
    }

    override func setupContentViews() {
        super.setupContentViews()

        switch state {
        case let .preparing(current, total):
            addSectionHeader("Playlist")
            addInfoView(
                title: "Status",
                value: "Preparing playlist...",
                description: String(localized: "Packaging the current playlist and its local tracks for one Apple TV session."),
            )
            addInfoView(
                title: "Progress",
                rawValue: "\(current) / \(max(total, 1))",
                description: String(localized: "Tracks prepared successfully for transfer."),
            )

        case let .ready(connectionInfo, plan, progress):
            addSectionHeader("Playlist")
            addInfoView(
                title: "Name",
                rawValue: plan.session.playlistName,
                description: String(localized: "The playlist that will replace the current Apple TV session."),
            )
            addInfoView(
                title: "Transferable Tracks",
                rawValue: "\(plan.transferableTracks.count)",
                description: String(localized: "Only tracks that already resolve to local files on this iPhone are sent."),
            )
            if !plan.skippedTrackIDs.isEmpty {
                addInfoView(
                    title: "Skipped",
                    rawValue: "\(plan.skippedTrackIDs.count)",
                    description: String(localized: "These tracks were not locally available on iPhone, so they were excluded from transfer."),
                )
            }
            if !session.preparedSkippedItems.isEmpty {
                addInfoView(
                    title: "Unreadable",
                    rawValue: "\(session.preparedSkippedItems.count)",
                    description: String(localized: "These songs could not be read from local storage and were left out."),
                )
                stackView.addArrangedSubviewWithMargin(makeViewSkippedObject().createView())
                stackView.addArrangedSubview(SeparatorView())
            }

            addSenderTransferSection(progress: progress)

            if initialTracks == nil {
                addSectionHeader("Apple TV")
                let activeReceiverName = progress.receiverDeviceName ?? selectedReceiverInfo?.deviceName.nilIfEmpty
                if let activeReceiverName {
                    addInfoView(
                        title: "Selected Apple TV",
                        rawValue: activeReceiverName,
                        description: String(localized: "Keep this Apple TV on the receive screen while it completes the playlist transfer."),
                    )
                    if progress.receiverDeviceName == nil,
                       let selectedReceiverInfo,
                       !isReceiverNearby(selectedReceiverInfo)
                    {
                        addInfoView(
                            title: "Status",
                            value: "Waiting for selected Apple TV...",
                            description: String(localized: "The scanned or selected Apple TV has not appeared nearby yet. Keep Muse Amp open on its receive screen and refresh if needed."),
                        )
                    }
                } else if receiverBrowser.devices.isEmpty {
                    addInfoView(
                        title: "Status",
                        value: "Searching for Apple TVs...",
                        description: String(localized: "Open Muse Amp on Apple TV to make it appear here."),
                    )
                } else {
                    for device in receiverBrowser.devices {
                        stackView.addArrangedSubviewWithMargin(makeReceiverView(device))
                        stackView.addArrangedSubview(SeparatorView())
                    }
                }

                addSectionHeader("Connect")
                addInfoView(
                    title: "Sender Name",
                    rawValue: connectionInfo.deviceName,
                    description: String(localized: "Apple TV will show this iPhone in its nearby sender list."),
                )
                addInfoView(
                    title: "Password",
                    rawValue: connectionInfo.password,
                    description: String(localized: "Enter this temporary code on Apple TV after selecting this sender."),
                )
                if let qrImageView = makeQRCodeView(connectionInfo: connectionInfo) {
                    stackView.addArrangedSubview(qrImageView)
                    stackView.addArrangedSubview(SeparatorView())
                }

                addSectionHeader("Actions")
                if canScanQRCode {
                    stackView.addArrangedSubviewWithMargin(makeScanQRCodeObject().createView())
                    stackView.addArrangedSubview(SeparatorView())
                }
                stackView.addArrangedSubviewWithMargin(makeRefreshReceiversObject().createView())
                stackView.addArrangedSubview(SeparatorView())
                stackView.addArrangedSubviewWithMargin(makeStopServerObject().createView())
                stackView.addArrangedSubview(SeparatorView())
            }

            stackView.addArrangedSubviewWithMargin(
                ConfigurableSectionFooterView().with(
                    footer: String(localized: "Keep both apps active. Apple TV pulls the playlist from this iPhone, so sending stops if either app leaves the foreground."),
                ),
            ) { $0.top /= 2 }

        case let .interrupted(message):
            addSectionHeader("Status")
            addInfoView(
                title: "Interrupted",
                rawValue: message,
                description: String(localized: "The Apple TV sender stopped before the playlist finished transferring."),
            )
            addSectionHeader("Actions")
            stackView.addArrangedSubviewWithMargin(makeDoneObject().createView())
            stackView.addArrangedSubview(SeparatorView())
        }
    }
}

extension SyncPlaylistAppleTVSenderViewController {
    @objc func dismissFormSheet() {
        navigationController?.dismiss(animated: true)
    }
}

private extension SyncPlaylistAppleTVSenderViewController {
    var canScanQRCode: Bool {
        #if targetEnvironment(macCatalyst)
            false
        #else
            UIImagePickerController.isSourceTypeAvailable(.camera)
        #endif
    }

    var playlist: Playlist? {
        guard let playlistID else { return nil }
        return environment.playlistStore.playlist(for: playlistID)
    }

    func startSession() {
        if let initialTracks {
            startSessionWithTracks(initialTracks)
        } else {
            startSessionWithPlaylist()
        }
    }

    func startSessionWithPlaylist() {
        startupTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            guard let playlist else {
                presentFailureAndPop(message: String(localized: "This playlist is no longer available."))
                return
            }

            do {
                let plan = try await session.prepareSender(
                    playlist: playlist,
                    includeLyrics: true,
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
                    plan: plan,
                    progress: session.senderProgress ?? .waiting(
                        playlistName: plan.session.playlistName,
                        totalTrackCount: plan.transferableTracks.count,
                    ),
                )
                refreshUI()
                presentSkippedNoticeIfNeeded()
            } catch {
                AppLog.error(self, "startSession failed playlistID=\(playlistID?.uuidString ?? "nil") error=\(error.localizedDescription)")
                await session.stopSender()
                presentFailureAndPop(message: error.localizedDescription)
            }
        }
    }

    func startSessionWithTracks(_ tracks: [AudioTrackRecord]) {
        startupTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            do {
                let plan = SyncPlaylistTransferPlan(
                    transferableTracks: tracks,
                    totalTrackCount: tracks.count,
                )
                try await session.prepareSender(
                    tracks: tracks,
                    session: plan.session,
                    password: selectedReceiverInfo?.pairingCode,
                    includeLyrics: true,
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
                    plan: plan,
                    progress: session.senderProgress ?? .waiting(
                        playlistName: String(localized: "Apple TV Session"),
                        totalTrackCount: tracks.count,
                    ),
                )
                refreshUI()
                presentSkippedNoticeIfNeeded()
            } catch {
                AppLog.error(self, "startSession tracks failed error=\(error.localizedDescription)")
                await session.stopSender()
                presentFailureAndPop(message: error.localizedDescription)
            }
        }
    }

    func handleBackgroundInterruption() {
        startupTask?.cancel()
        Task {
            await session.stopSender()
        }
        state = .interrupted(String(localized: "Sending was interrupted because the app moved to the background."))
        refreshUI()
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

    func refreshUI() {
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        setupContentViews()
    }

    func applySenderProgress(_ progress: SyncSenderTransferProgress) {
        guard case let .ready(connectionInfo, plan, _) = state else {
            return
        }
        state = .ready(
            connectionInfo: connectionInfo,
            plan: plan,
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
                value: "Waiting for Apple TV...",
                description: String(localized: "Open the receive screen on Apple TV, choose this iPhone, and enter the temporary password there."),
            )

        case .receiverConnected:
            addInfoView(
                title: "Status",
                value: "Apple TV Connected",
                description: String(localized: "Apple TV authenticated successfully and is about to request the playlist manifest."),
            )

        case .manifestServed:
            addInfoView(
                title: "Status",
                value: "Sending Playlist Info...",
                description: String(localized: "Apple TV is loading the playlist metadata and preparing to pull audio files."),
            )

        case .sendingTrack:
            addInfoView(
                title: "Status",
                value: "Sending Playlist...",
                description: String(localized: "Apple TV is actively downloading the transferable tracks for this playlist."),
            )
            addInfoView(
                title: "Progress",
                rawValue: "\(progress.currentTrackCount) / \(max(progress.totalTrackCount, 1))",
                description: String(localized: "Unique audio files served from this iPhone to Apple TV so far."),
            )
            if let currentTrackTitle = progress.currentTrackTitle {
                addInfoView(
                    title: "Current Song",
                    rawValue: currentTrackTitle,
                    description: String(localized: "The track Apple TV is pulling right now."),
                )
            }

        case .completed:
            addInfoView(
                title: "Status",
                value: "iPhone Transfer Complete",
                description: String(localized: "All transferable audio files were served to Apple TV. It may still be importing them locally."),
            )
            addInfoView(
                title: "Progress",
                rawValue: "\(progress.currentTrackCount) / \(max(progress.totalTrackCount, 1))",
                description: String(localized: "Unique playlist files delivered from this iPhone to Apple TV."),
            )
        }

        if let receiverDeviceName = progress.receiverDeviceName {
            addInfoView(
                title: "Receiver",
                rawValue: receiverDeviceName,
                description: String(localized: "The Apple TV currently receiving this playlist session."),
            )
        }
    }

    func addInfoView(
        title: String.LocalizationValue,
        value: String.LocalizationValue,
        description: String? = nil,
    ) {
        addInfoView(title: title, rawValue: String(localized: value), description: description)
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

    func makeReceiverView(_ device: DiscoveredDevice) -> UIView {
        let view = ConfigurableActionView { [weak self] _ in
            guard let self else {
                return
            }
            let selectedReceiverInfo = SyncReceiverHandshakeInfo(
                serviceName: device.serviceName,
                deviceName: device.deviceName,
            )
            await MainActor.run {
                self.selectedReceiverInfo = selectedReceiverInfo
                self.refreshUI()
            }
        }
        view.configure(icon: UIImage(systemName: "tv"))
        view.configure(title: device.deviceName)
        view.configure(
            description: String(localized: "Tap to target this Apple TV, then keep it on the receive screen and enter the sender password there."),
        )
        return view
    }

    func makeScanQRCodeObject() -> ConfigurableObject {
        ConfigurableObject(
            icon: "qrcode.viewfinder",
            title: "Scan Apple TV QR",
            explain: "Scan the QR code shown on Apple TV to select that receiver.",
            ephemeralAnnotation: .action { [weak self] _ in
                await MainActor.run { self?.openQRScannerIfAvailable() }
            },
        )
    }

    func makeRefreshReceiversObject() -> ConfigurableObject {
        ConfigurableObject(
            icon: "arrow.clockwise",
            title: "Refresh Apple TVs",
            explain: "Search again for Apple TVs on the same local network.",
            ephemeralAnnotation: .action { [weak self] _ in
                guard let self else {
                    return
                }
                receiverBrowser.stop()
                receiverBrowser.start()
                refreshUI()
            },
        )
    }

    func makeStopServerObject() -> ConfigurableObject {
        ConfigurableObject(
            icon: "stop.circle",
            title: "Stop Sharing",
            explain: "Stop sending this playlist to Apple TV.",
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
            explain: "Return to the playlist.",
            ephemeralAnnotation: .action { [weak self] _ in
                await MainActor.run {
                    _ = self?.navigationController?.popViewController(animated: true)
                }
            },
        )
    }

    func openQRScannerIfAvailable() {
        guard canScanQRCode else {
            return
        }

        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            DispatchQueue.main.async {
                guard let self else {
                    return
                }
                guard granted else {
                    self.presentErrorAlert(
                        title: String(localized: "Camera Access Needed"),
                        message: String(localized: "Allow camera access in Settings or choose an Apple TV from nearby discovery instead."),
                    )
                    return
                }
                #if !targetEnvironment(macCatalyst)
                    let scanner = SyncQRCodeScannerViewController { [weak self] scannedValue in
                        self?.handleScannedReceiverInfo(scannedValue)
                    }
                    scanner.modalPresentationStyle = .fullScreen
                    self.present(scanner, animated: true)
                #endif
            }
        }
    }

    func handleScannedReceiverInfo(_ scannedValue: String) {
        guard let data = scannedValue.data(using: .utf8) else {
            presentErrorAlert(
                title: String(localized: "Invalid QR Code"),
                message: String(localized: "The scanned Apple TV QR code could not be read."),
            )
            return
        }

        do {
            let receiverInfo = try JSONDecoder().decode(SyncReceiverHandshakeInfo.self, from: data)
            guard SyncConstants.isCompatible(protocolVersion: receiverInfo.protocolVersion) else {
                AppLog.warning(
                    self,
                    "handleScannedReceiverInfo protocol mismatch scanned=\(receiverInfo.protocolVersion) expected=\(SyncConstants.protocolVersion)",
                )
                presentErrorAlert(
                    title: String(localized: "Unsupported Apple TV"),
                    message: String(localized: "This Apple TV is using an incompatible transfer protocol version."),
                )
                return
            }

            selectedReceiverInfo = receiverInfo
            refreshUI()
            let receiverBrowser = receiverBrowser
            Task { @MainActor [weak self, receiverBrowser] in
                guard let self else {
                    return
                }
                _ = await receiverBrowser.resolveService(named: receiverInfo.serviceName)
                refreshUI()
            }
        } catch {
            AppLog.warning(self, "handleScannedReceiverInfo decode failed error=\(error.localizedDescription)")
            presentErrorAlert(
                title: String(localized: "Invalid QR Code"),
                message: error.localizedDescription,
            )
        }
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

    func presentErrorAlert(title: String, message: String) {
        let alert = AlertViewController(title: title, message: message) { context in
            context.addAction(title: String(localized: "OK"), attribute: .accent) {
                context.dispose()
            }
        }
        present(alert, animated: true)
    }

    func presentFailureAndPop(message: String) {
        let alert = AlertViewController(
            title: String(localized: "Unable to Share Playlist"),
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

    func isReceiverNearby(_ receiverInfo: SyncReceiverHandshakeInfo) -> Bool {
        receiverBrowser.devices.contains { $0.serviceName == receiverInfo.serviceName }
    }
}
