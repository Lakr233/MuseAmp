//
//  SyncServerStatusViewController.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import AlertController
import AmMusicDatabaseKit
import ConfigurableKit
import UIKit

final class SyncServerStatusViewController: StackScrollController {
    enum State {
        case preparing(current: Int, total: Int)
        case ready(connectionInfo: SyncConnectionInfo, songsReady: Int)
        case interrupted(String)
    }

    let environment: AppEnvironment
    let tracks: [AudioTrackRecord]
    let session: SyncTransferSession

    private var state: State
    private var startupTask: Task<Void, Never>?
    private lazy var backgroundInterruptionObserver = SyncBackgroundInterruptionObserver { [weak self] in
        self?.handleBackgroundInterruption()
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
        backgroundInterruptionObserver.start()
        startSession()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        UIApplication.shared.isIdleTimerDisabled = true
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        UIApplication.shared.isIdleTimerDisabled = false
        if isMovingFromParent {
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
            )
            addInfoView(
                title: "Progress",
                value: "\(current) / \(max(total, 1))",
            )

        case let .ready(connectionInfo, songsReady):
            addSectionHeader("Server")
            addInfoView(title: "Status", value: String(localized: "Ready"))
            addInfoView(title: "Service Name", value: connectionInfo.serviceName)
            addEndpointView(connectionInfo: connectionInfo)
            addInfoView(title: "Password", value: connectionInfo.password)

            addSectionHeader("QR Code")
            if let qrImageView = makeQRCodeView(connectionInfo: connectionInfo) {
                stackView.addArrangedSubview(qrImageView)
            }
            stackView.addArrangedSubview(SeparatorView())

            addSectionHeader("Statistics")
            addInfoView(title: "Songs Ready", value: "\(songsReady)")

            addSectionHeader("Actions")
            stackView.addArrangedSubviewWithMargin(makeStopServerObject().createView())
            stackView.addArrangedSubview(SeparatorView())
            stackView.addArrangedSubviewWithMargin(
                ConfigurableSectionFooterView().with(
                    footer: String(localized: "Keep the app active on both devices. Transfers stop if either app moves to the background."),
                ),
            ) { $0.top /= 2 }

        case let .interrupted(message):
            addSectionHeader("Server")
            addInfoView(title: "Status", value: String(localized: "Interrupted"))
            addInfoView(title: "Message", value: message)

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
                )
                refreshUI()
            } catch {
                AppLog.error(self, "startSession failed: \(error.localizedDescription)")
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
        value: String,
        menuBuilder: (() -> [UIMenuElement])? = nil,
    ) {
        let view = ConfigurableInfoView()
        view.configure(icon: UIImage(systemName: "info.circle"))
        view.configure(title: String(localized: title))
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
        imageView.translatesAutoresizingMaskIntoConstraints = false

        let container = UIView()
        container.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 240),
            imageView.heightAnchor.constraint(equalToConstant: 240),
            container.heightAnchor.constraint(equalTo: imageView.heightAnchor),
        ])
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
        ) { context in
            context.addAction(title: String(localized: "OK"), attribute: .accent) {
                context.dispose { [weak self] in
                    self?.navigationController?.popViewController(animated: true)
                }
            }
        }
        present(alert, animated: true)
    }
}
