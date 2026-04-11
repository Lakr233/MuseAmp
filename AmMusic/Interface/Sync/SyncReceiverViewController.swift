//
//  SyncReceiverViewController.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import AlertController
import AVFoundation
import ConfigurableKit
import UIKit

final class SyncReceiverViewController: StackScrollController {
    let environment: AppEnvironment
    let session: SyncTransferSession

    init(environment: AppEnvironment) {
        self.environment = environment
        session = environment.makeSyncTransferSession()
        super.init(nibName: nil, bundle: nil)
        title = String(localized: "Receiving")
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        session.onDiscoveredDevicesChanged = { [weak self] _ in
            self?.refreshUI()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        session.startBrowsing()
        refreshUI()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        session.stopBrowsing()
        if isMovingFromParent {
            session.stopReceiver()
        }
    }

    override func setupContentViews() {
        super.setupContentViews()

        addSectionHeader("Devices")
        if session.discoveredDevices.isEmpty {
            let infoView = ConfigurableInfoView()
            infoView.configure(icon: UIImage(systemName: "magnifyingglass"))
            infoView.configure(title: String(localized: "Searching..."))
            infoView.configure(value: String(localized: "Scanning your local network"))
            stackView.addArrangedSubviewWithMargin(infoView)
            stackView.addArrangedSubview(SeparatorView())
        } else {
            for device in session.discoveredDevices {
                stackView.addArrangedSubviewWithMargin(makeDeviceView(device))
                stackView.addArrangedSubview(SeparatorView())
            }
        }

        addSectionHeader("Manual Connection")
        if canScanQRCode {
            stackView.addArrangedSubviewWithMargin(makeScanQRCodeObject().createView())
            stackView.addArrangedSubview(SeparatorView())
        }
        stackView.addArrangedSubviewWithMargin(makeManualAddressObject().createView())
        stackView.addArrangedSubview(SeparatorView())
        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionFooterView().with(
                footer: String(localized: "Make sure both devices are on the same local network."),
            ),
        ) { $0.top /= 2 }
    }
}

private extension SyncReceiverViewController {
    var canScanQRCode: Bool {
        #if targetEnvironment(macCatalyst)
            false
        #else
            UIImagePickerController.isSourceTypeAvailable(.camera)
        #endif
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

    func makeDeviceView(_ device: DiscoveredDevice) -> UIView {
        let view = ConfigurableActionView { [weak self] _ in
            let this = self
            await MainActor.run { this?.promptPassword(for: device) }
        }
        view.configure(icon: UIImage(systemName: "iphone.gen3"))
        view.configure(title: device.deviceName)
        view.configure(description: device.primaryDisplayAddress)
        return view
    }

    func makeScanQRCodeObject() -> ConfigurableObject {
        ConfigurableObject(
            icon: "qrcode.viewfinder",
            title: "Scan QR Code",
            explain: "Scan the sender's temporary transfer QR code.",
            ephemeralAnnotation: .action { [weak self] _ in
                await MainActor.run { self?.openQRScannerIfAvailable() }
            },
        )
    }

    func makeManualAddressObject() -> ConfigurableObject {
        ConfigurableObject(
            icon: "keyboard",
            title: "Enter Address",
            explain: "Type a host name or IP address and port.",
            ephemeralAnnotation: .action { [weak self] _ in
                await MainActor.run { self?.promptManualAddress() }
            },
        )
    }

    func promptPassword(for device: DiscoveredDevice) {
        let alert = AlertInputViewController(
            title: String(localized: "Enter Password"),
            message: device.deviceName,
            placeholder: String(localized: "6-digit password"),
            text: "",
        ) { [weak self] password in
            let trimmed = password.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return
            }
            self?.connect(
                endpoint: device.preferredEndpoint ?? device.fallbackEndpoints.first,
                password: trimmed,
            )
        }
        present(alert, animated: true)
    }

    func promptManualAddress() {
        let alert = AlertInputViewController(
            title: String(localized: "Enter Address"),
            message: String(localized: "Use hostname:port, IPv4:port, or [IPv6]:port."),
            placeholder: "host-or-name:port",
            text: "",
        ) { [weak self] value in
            guard let self else {
                return
            }
            do {
                let endpoint = try SyncEndpoint.parse(value)
                let passwordAlert = AlertInputViewController(
                    title: String(localized: "Enter Password"),
                    message: endpoint.displayString,
                    placeholder: String(localized: "6-digit password"),
                    text: "",
                ) { [weak self] password in
                    let trimmed = password.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else {
                        return
                    }
                    self?.connect(endpoint: endpoint, password: trimmed)
                }
                present(passwordAlert, animated: true)
            } catch {
                AppLog.warning(self, "promptManualAddress parse failed: \(error.localizedDescription)")
                presentErrorAlert(
                    title: String(localized: "Invalid Address"),
                    message: error.localizedDescription,
                )
            }
        }
        present(alert, animated: true)
    }

    func connect(endpoint: SyncEndpoint?, password: String) {
        guard let endpoint else {
            presentErrorAlert(
                title: String(localized: "Connection Failed"),
                message: String(localized: "No reachable address was available for the selected device."),
            )
            return
        }

        let progress = AlertProgressIndicatorViewController(
            title: String(localized: "Connecting"),
            message: endpoint.displayString,
        )
        present(progress, animated: true)

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            do {
                let token = try await session.authenticate(
                    endpoint: endpoint,
                    password: password,
                )
                progress.dismiss(animated: true) { [weak self] in
                    self?.openTransferProgress(endpoint: endpoint, token: token)
                }
            } catch {
                AppLog.error(self, "connect failed endpoint=\(endpoint.displayString) error=\(error.localizedDescription)")
                progress.dismiss(animated: true) { [weak self] in
                    self?.presentErrorAlert(
                        title: String(localized: "Connection Failed"),
                        message: error.localizedDescription,
                    )
                }
            }
        }
    }

    func openTransferProgress(endpoint: SyncEndpoint, token: String) {
        navigationController?.pushViewController(
            SyncTransferProgressViewController(
                session: session,
                endpoint: endpoint,
                token: token,
            ),
            animated: true,
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
                        message: String(localized: "Allow camera access in Settings or use manual address entry instead."),
                    )
                    return
                }
                #if !targetEnvironment(macCatalyst)
                    let scanner = SyncQRCodeScannerViewController { [weak self] scannedValue in
                        self?.handleScannedConnectionInfo(scannedValue)
                    }
                    scanner.modalPresentationStyle = .fullScreen
                    self.present(scanner, animated: true)
                #endif
            }
        }
    }

    func handleScannedConnectionInfo(_ scannedValue: String) {
        guard let data = scannedValue.data(using: .utf8) else {
            presentErrorAlert(
                title: String(localized: "Invalid QR Code"),
                message: String(localized: "The scanned QR code could not be read."),
            )
            return
        }

        do {
            let connectionInfo = try JSONDecoder().decode(SyncConnectionInfo.self, from: data)
            connectUsingConnectionInfo(connectionInfo)
        } catch {
            AppLog.warning(self, "handleScannedConnectionInfo decode failed: \(error.localizedDescription)")
            presentErrorAlert(
                title: String(localized: "Invalid QR Code"),
                message: error.localizedDescription,
            )
        }
    }

    func connectUsingConnectionInfo(_ connectionInfo: SyncConnectionInfo) {
        let progress = AlertProgressIndicatorViewController(
            title: String(localized: "Connecting"),
            message: connectionInfo.deviceName,
        )
        present(progress, animated: true)

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            let endpoints = await session.resolveEndpoints(for: connectionInfo)
            for endpoint in endpoints {
                do {
                    let token = try await session.authenticate(
                        endpoint: endpoint,
                        password: connectionInfo.password,
                    )
                    progress.dismiss(animated: true) { [weak self] in
                        self?.openTransferProgress(endpoint: endpoint, token: token)
                    }
                    return
                } catch {
                    AppLog.warning(self, "connectUsingConnectionInfo failed endpoint=\(endpoint.displayString) error=\(error.localizedDescription)")
                }
            }

            progress.dismiss(animated: true) { [weak self] in
                self?.presentErrorAlert(
                    title: String(localized: "Connection Failed"),
                    message: String(localized: "No reachable address was available for the selected device."),
                )
            }
        }
    }

    func presentErrorAlert(title: String, message: String) {
        let alert = AlertViewController(title: title, message: message) { context in
            context.addAction(title: String(localized: "OK"), attribute: .accent) {
                context.dispose()
            }
        }
        present(alert, animated: true)
    }
}

#if !targetEnvironment(macCatalyst)
    private final class SyncQRCodeScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
        private let captureSession = AVCaptureSession()
        private let onCodeScanned: (String) -> Void
        private let previewLayer = AVCaptureVideoPreviewLayer()
        private var hasFinished = false
        private var captureDevice: AVCaptureDevice?
        private var rotationObservation: NSKeyValueObservation?

        init(onCodeScanned: @escaping (String) -> Void) {
            self.onCodeScanned = onCodeScanned
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError()
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black

            previewLayer.session = captureSession
            previewLayer.videoGravity = .resizeAspectFill
            view.layer.addSublayer(previewLayer)

            let closeButton = UIButton(type: .system)
            closeButton.tintColor = .white
            closeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
            closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
            closeButton.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(closeButton)
            NSLayoutConstraint.activate([
                closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
                closeButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
                closeButton.widthAnchor.constraint(equalToConstant: 32),
                closeButton.heightAnchor.constraint(equalToConstant: 32),
            ])

            configureCaptureSession()
            configureRotation()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            previewLayer.frame = view.bounds
            if #unavailable(iOS 17.0) {
                updatePreviewOrientationLegacy()
            }
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            let session = captureSession
            DispatchQueue.global(qos: .userInitiated).async {
                if !session.isRunning {
                    session.startRunning()
                }
            }
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            let session = captureSession
            DispatchQueue.global(qos: .userInitiated).async {
                if session.isRunning {
                    session.stopRunning()
                }
            }
        }

        override func viewWillTransition(
            to size: CGSize,
            with coordinator: any UIViewControllerTransitionCoordinator,
        ) {
            super.viewWillTransition(to: size, with: coordinator)
            if #unavailable(iOS 17.0) {
                coordinator.animate(alongsideTransition: { _ in
                    self.updatePreviewOrientationLegacy()
                })
            }
        }

        func metadataOutput(
            _: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from _: AVCaptureConnection,
        ) {
            guard !hasFinished,
                  let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  object.type == .qr,
                  let value = object.stringValue
            else {
                return
            }

            hasFinished = true
            captureSession.stopRunning()
            dismiss(animated: true) { [onCodeScanned] in
                onCodeScanned(value)
            }
        }

        @objc func closeTapped() {
            dismiss(animated: true)
        }

        private func configureCaptureSession() {
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device)
            else {
                return
            }

            captureDevice = device

            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
            }

            let output = AVCaptureMetadataOutput()
            if captureSession.canAddOutput(output) {
                captureSession.addOutput(output)
                output.setMetadataObjectsDelegate(self, queue: .main)
                output.metadataObjectTypes = [.qr]
            }
        }

        private func configureRotation() {
            if #available(iOS 17.0, *) {
                guard let device = captureDevice else { return }
                let coordinator = AVCaptureDevice.RotationCoordinator(
                    device: device,
                    previewLayer: previewLayer,
                )
                previewLayer.connection?.videoRotationAngle = coordinator.videoRotationAngleForHorizonLevelPreview
                rotationObservation = coordinator.observe(
                    \.videoRotationAngleForHorizonLevelPreview,
                    options: .new,
                ) { [weak self] coord, _ in
                    DispatchQueue.main.async {
                        self?.previewLayer.connection?.videoRotationAngle = coord.videoRotationAngleForHorizonLevelPreview
                    }
                }
            }
        }

        private func updatePreviewOrientationLegacy() {
            guard let connection = previewLayer.connection, connection.isVideoOrientationSupported else {
                return
            }
            let interfaceOrientation = view.window?.windowScene?.interfaceOrientation ?? .portrait
            switch interfaceOrientation {
            case .portrait: connection.videoOrientation = .portrait
            case .landscapeLeft: connection.videoOrientation = .landscapeLeft
            case .landscapeRight: connection.videoOrientation = .landscapeRight
            case .portraitUpsideDown: connection.videoOrientation = .portraitUpsideDown
            default: connection.videoOrientation = .portrait
            }
        }
    }
#endif
