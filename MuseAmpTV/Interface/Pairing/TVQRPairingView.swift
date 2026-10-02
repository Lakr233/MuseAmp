import SnapKit
import UIKit

@MainActor
final class TVQRPairingView: UIStackView {
    // MARK: - QR + Instruction

    private let qrImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .white
        imageView.layer.magnificationFilter = .nearest
        imageView.layer.minificationFilter = .nearest
        imageView.layer.cornerRadius = 4
        imageView.layer.cornerCurve = .continuous
        imageView.layer.masksToBounds = true
        imageView.layer.shadowColor = UIColor.black.cgColor
        imageView.layer.shadowOpacity = 0.35
        imageView.layer.shadowRadius = 20
        imageView.layer.shadowOffset = CGSize(width: 0, height: 8)
        imageView.isHidden = true
        return imageView
    }()

    private let instructionLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(
            ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize,
            weight: .bold,
        )
        label.textColor = UIColor.white.withAlphaComponent(0.85)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.text = String(localized: "On an iPhone with Muse Amp installed, use the system camera to scan the QR code displayed on this Apple TV, then select the songs to transfer.")
        return label
    }()

    // MARK: - Device Discovery

    private let deviceMenuButton: UIButton = {
        var configuration = UIButton.Configuration.gray()
        configuration.baseForegroundColor = UIColor.white.withAlphaComponent(0.92)
        configuration.imagePlacement = .trailing
        configuration.imagePadding = 12
        configuration.cornerStyle = .large
        configuration.titleAlignment = .center
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: 22, leading: 32, bottom: 22, trailing: 32,
        )
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(
                ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize,
                weight: .bold,
            )
            return outgoing
        }

        let button = UIButton(type: .system)
        button.configuration = configuration
        button.showsMenuAsPrimaryAction = true
        return button
    }()

    private var currentDevices: [DiscoveredDevice] = []

    var onSenderSelected: (DiscoveredDevice) -> Void = { _ in }

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)

        axis = .vertical
        alignment = .center
        spacing = 64

        addArrangedSubview(qrImageView)
        addArrangedSubview(instructionLabel)
        addArrangedSubview(deviceMenuButton)

        qrImageView.snp.makeConstraints { make in
            make.width.height.equalTo(320)
        }

        deviceMenuButton.snp.makeConstraints { make in
            make.width.equalTo(UIScreen.main.bounds.width / 4)
        }

        updateDeviceMenu()
    }

    @available(*, unavailable)
    required init(coder _: NSCoder) {
        fatalError()
    }

    // MARK: - Configure

    func configure(content: AMTVUploadWaitingContent) {
        if let payload = content.qrPayload {
            qrImageView.image = Self.makeQRCodeImage(from: payload)
        }
        qrImageView.isHidden = qrImageView.image == nil

        isAccessibilityElement = false
        accessibilityTraits = .staticText
        accessibilityLabel = [
            content.message,
            content.qrPayload == nil ? "" : String(localized: "QR code available"),
        ]
        .filter { !$0.isEmpty }
        .joined(separator: ", ")
    }

    func updateDiscoveredSenders(_ devices: [DiscoveredDevice]) {
        let newIDs = devices.map(\.serviceName)
        let oldIDs = currentDevices.map(\.serviceName)
        guard newIDs != oldIDs else { return }

        currentDevices = devices
        updateDeviceMenu()
    }

    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        [deviceMenuButton]
    }

    // MARK: - Device Menu

    private func updateDeviceMenu() {
        let searching = currentDevices.isEmpty
        var configuration = deviceMenuButton.configuration ?? .gray()
        configuration.showsActivityIndicator = searching
        configuration.image = searching ? nil : UIImage(systemName: "chevron.down")
        configuration.title = searching
            ? String(localized: "Searching for nearby devices…")
            : String(localized: "Nearby Devices (\(currentDevices.count))")
        deviceMenuButton.configuration = configuration
        let wasEnabled = deviceMenuButton.isEnabled
        deviceMenuButton.isEnabled = !searching

        if searching {
            deviceMenuButton.menu = nil
        } else {
            let deviceActions = currentDevices.map { device in
                UIAction(
                    title: device.deviceName,
                    subtitle: device.preferredEndpoint?.host ?? device.serviceName,
                    image: UIImage(systemName: Self.symbolName(for: device.deviceName)),
                ) { [weak self] _ in
                    self?.onSenderSelected(device)
                }
            }
            deviceMenuButton.menu = UIMenu(children: [UIMenu(options: .displayInline, children: deviceActions)])
        }

        if !wasEnabled, deviceMenuButton.isEnabled {
            setNeedsFocusUpdate()
            updateFocusIfNeeded()
        }
    }

    // MARK: - Helpers

    private static func makeQRCodeImage(from payload: String) -> UIImage? {
        guard let data = payload.data(using: .utf8),
              let filter = CIFilter(name: "CIQRCodeGenerator")
        else {
            return nil
        }

        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let outputImage = filter.outputImage else {
            return nil
        }

        let transform = CGAffineTransform(scaleX: 10, y: 10)
        return UIImage(ciImage: outputImage.transformed(by: transform))
    }

    private static func symbolName(for deviceName: String) -> String {
        let lower = deviceName.lowercased()
        if lower.contains("iphone") { return "iphone" }
        if lower.contains("ipad") { return "ipad.landscape" }
        if lower.contains("macbook") { return "laptopcomputer" }
        if lower.contains("imac") { return "desktopcomputer" }
        if lower.contains("mac mini") { return "macmini" }
        if lower.contains("mac studio") { return "macstudio" }
        if lower.contains("mac pro") { return "macpro.gen3" }
        if lower.contains("mac") { return "laptopcomputer" }
        return "wifi"
    }
}
