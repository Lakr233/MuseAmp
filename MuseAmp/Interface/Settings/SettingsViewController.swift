//
//  SettingsViewController.swift
//  MuseAmp
//
//  Created by @Lakr233 on 2026/04/11.
//

import ConfigurableKit
import SnapKit
import Then
import UIKit

final class SettingsViewController: StackScrollController {
    let environment: AppEnvironment
    private var downloadsObject: ConfigurableObject?
    var serverProfileView: ConfigurableInfoView?
    lazy var serverProfileImportCoordinator = ServerProfileImportCoordinator(
        viewController: self,
        environment: environment,
        onConfigurationChanged: { [weak self] in
            self?.refreshServerProfile()
        },
    )

    init(environment: AppEnvironment) {
        self.environment = environment
        super.init(nibName: nil, bundle: nil)
        title = String(localized: "Settings")
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        scrollView.applySoftEdgeEffects()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshDownloadsExplain()
        refreshServerProfile()
    }

    override func setupContentViews() {
        super.setupContentViews()

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionHeaderView().with(header: String(localized: "Server")),
        ) { $0.bottom /= 2 }
        stackView.addArrangedSubview(SeparatorView())
        stackView.addArrangedSubviewWithMargin(makeServerConfigurationView())
        stackView.addArrangedSubview(SeparatorView())

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionHeaderView().with(header: String(localized: "Transfer")),
        ) { $0.bottom /= 2 }
        stackView.addArrangedSubview(SeparatorView())
        stackView.addArrangedSubviewWithMargin(makeTransferObject().createView())
        stackView.addArrangedSubview(SeparatorView())
        if #available(iOS 16.0, macCatalyst 17.0, *) {
            stackView.addArrangedSubviewWithMargin(makeAppleMusicImportObject().createView())
            stackView.addArrangedSubview(SeparatorView())
        }
        let downloads = makeDownloadsObject()
        downloadsObject = downloads
        stackView.addArrangedSubviewWithMargin(downloads.createView())
        stackView.addArrangedSubview(SeparatorView())

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionHeaderView().with(header: String(localized: "Tweaks")),
        ) { $0.bottom /= 2 }
        stackView.addArrangedSubview(SeparatorView())
        stackView.addArrangedSubviewWithMargin(makeLyricsAutoConvertChineseObject().createView())
        stackView.addArrangedSubview(SeparatorView())
        stackView.addArrangedSubviewWithMargin(makeCleanSongTitleObject().createView())
        stackView.addArrangedSubview(SeparatorView())

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionHeaderView().with(header: String(localized: "Diagnostics")),
        ) { $0.bottom /= 2 }
        stackView.addArrangedSubview(SeparatorView())
        stackView.addArrangedSubviewWithMargin(makeLogsObject().createView())
        stackView.addArrangedSubview(SeparatorView())
        stackView.addArrangedSubviewWithMargin(makeRebuildDatabaseObject().createView())
        stackView.addArrangedSubview(SeparatorView())
        stackView.addArrangedSubviewWithMargin(makeRebuildAllLyricsIndexObject().createView())
        stackView.addArrangedSubview(SeparatorView())

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionHeaderView().with(header: String(localized: "About")),
        ) { $0.bottom /= 2 }
        stackView.addArrangedSubview(SeparatorView())
        stackView.addArrangedSubviewWithMargin(makePrivacyPolicyObject().createView())
        stackView.addArrangedSubview(SeparatorView())
        stackView.addArrangedSubviewWithMargin(makeOpenSourceLicensesObject().createView())
        stackView.addArrangedSubview(SeparatorView())

        buildFooter()
    }
}

private extension SettingsViewController {
    func refreshDownloadsExplain() {
        let storedSize = ByteCountFormatter.string(
            fromByteCount: environment.downloadStore.localLibraryStorageSize(),
            countStyle: .file,
        )
        downloadsObject?.explain = "Download queue, progress, and local storage.\nStored Locally: \(storedSize)"
    }
}

extension SettingsViewController {
    func makeDownloadsObject() -> ConfigurableObject {
        let storedSize = ByteCountFormatter.string(
            fromByteCount: environment.downloadStore.localLibraryStorageSize(),
            countStyle: .file,
        )
        return ConfigurableObject(
            icon: "arrow.down.circle",
            title: "Downloads",
            explain: "Download queue, progress, and local storage.\nStored Locally: \(storedSize)",
            ephemeralAnnotation: .action { [weak self] _ in
                guard let self else { return }
                openDownloads()
            },
        )
    }

    func makeLogsObject() -> ConfigurableObject {
        ConfigurableObject(
            icon: "doc.text.magnifyingglass",
            title: "View Logs",
            explain: "Inspect file-backed app logs for database, downloads, and indexing issues.",
            ephemeralAnnotation: .action { [weak self] _ in
                guard let self else { return }
                openLogs()
            },
        )
    }

    func buildFooter() {
        let info = Bundle.main.infoDictionary
        let marketingVersion = info?["CFBundleShortVersionString"] as? String ?? "?"
        let buildVersion = info?["CFBundleVersion"] as? String ?? "?"

        let label = UILabel().then {
            $0.text = String(format: String(localized: "Version %@ (%@)"), marketingVersion, buildVersion)
            $0.font = .monospacedSystemFont(
                ofSize: UIFont.preferredFont(forTextStyle: .caption2).pointSize,
                weight: .regular,
            )
            $0.textColor = .tertiaryLabel
            $0.textAlignment = .center
            $0.numberOfLines = 0
        }

        let container = UIView().then {
            $0.addSubview(label)
            label.snp.makeConstraints {
                $0.edges.equalToSuperview().inset(
                    UIEdgeInsets(
                        top: InterfaceStyle.Spacing.small,
                        left: InterfaceStyle.Spacing.small,
                        bottom: InterfaceStyle.Spacing.medium,
                        right: InterfaceStyle.Spacing.small,
                    ),
                )
            }
        }
        stackView.addArrangedSubview(container)
    }
}
