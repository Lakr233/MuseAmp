import ConfigurableKit
import SnapKit
import Then
import UIKit

final class SettingsViewController: StackScrollController {
    let environment: AppEnvironment

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
    }

    override func setupContentViews() {
        super.setupContentViews()

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionHeaderView().with(header: String(localized: "API"))
        ) { $0.bottom /= 2 }
        stackView.addArrangedSubview(SeparatorView())
        stackView.addArrangedSubviewWithMargin(makeAPIEndpointView())
        stackView.addArrangedSubview(SeparatorView())
        stackView.addArrangedSubviewWithMargin(makeAuthorizationView())
        stackView.addArrangedSubview(SeparatorView())

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionHeaderView().with(header: String(localized: "Downloads"))
        ) { $0.bottom /= 2 }
        stackView.addArrangedSubview(SeparatorView())
        stackView.addArrangedSubviewWithMargin(makeDownloadsObject().createView())
        stackView.addArrangedSubview(SeparatorView())

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionHeaderView().with(header: String(localized: "Lyrics"))
        ) { $0.bottom /= 2 }
        stackView.addArrangedSubview(SeparatorView())
        stackView.addArrangedSubviewWithMargin(makeLyricsAutoConvertChineseObject().createView())
        stackView.addArrangedSubview(SeparatorView())

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionHeaderView().with(header: String(localized: "Diagnostics"))
        ) { $0.bottom /= 2 }
        stackView.addArrangedSubview(SeparatorView())
        stackView.addArrangedSubviewWithMargin(makeLogsObject().createView())
        stackView.addArrangedSubview(SeparatorView())
        stackView.addArrangedSubviewWithMargin(makeClearAPICacheObject().createView())
        stackView.addArrangedSubview(SeparatorView())
        stackView.addArrangedSubviewWithMargin(makeRebuildDatabaseObject().createView())
        stackView.addArrangedSubview(SeparatorView())

        buildFooter()
    }
}

extension SettingsViewController {
    func makeDownloadsObject() -> ConfigurableObject {
        ConfigurableObject(
            icon: "arrow.down.circle",
            title: "Downloads",
            explain: "Download queue and progress.",
            ephemeralAnnotation: .action { [weak self] _ in
                guard let self else { return }
                openDownloads()
            }
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
            }
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
                weight: .regular
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
                        right: InterfaceStyle.Spacing.small
                    )
                )
            }
        }
        stackView.addArrangedSubview(container)
    }
}
