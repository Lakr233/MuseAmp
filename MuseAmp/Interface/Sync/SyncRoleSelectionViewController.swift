//
//  SyncRoleSelectionViewController.swift
//  MuseAmp
//
//  Created by @Lakr233 on 2026/04/11.
//

import ConfigurableKit
import Then
import UIKit

final class SyncRoleSelectionViewController: StackScrollController {
    let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
        super.init(nibName: nil, bundle: nil)
        title = String(localized: "Transfer Songs")
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

    override func setupContentViews() {
        super.setupContentViews()

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionHeaderView().with(header: String(localized: "Choose Mode")),
        ) { $0.bottom /= 2 }
        stackView.addArrangedSubview(SeparatorView())
        stackView.addArrangedSubviewWithMargin(makeSendObject().createView())
        stackView.addArrangedSubview(SeparatorView())
        stackView.addArrangedSubviewWithMargin(makeReceiveObject().createView())
        stackView.addArrangedSubview(SeparatorView())
    }
}

private extension SyncRoleSelectionViewController {
    func makeSendObject() -> ConfigurableObject {
        ConfigurableObject(
            icon: "square.and.arrow.up",
            title: "Send Songs",
            explain: "Select songs and let another device download them.",
            ephemeralAnnotation: .action { [weak self] _ in
                guard let self else {
                    return
                }
                presentSendPicker()
            },
        )
    }

    func presentSendPicker() {
        let environment = environment
        let picker = SyncContentPickerViewController(
            environment: environment,
            title: String(localized: "Send Songs"),
            emptySelectionMessage: String(localized: "Select at least one item to send."),
            checksLocalNetworkPermission: false,
        ) { tracks, picker in
            let serverVC = SyncServerStatusViewController(
                tracks: tracks,
                environment: environment,
            )
            picker.navigationController?.pushViewController(serverVC, animated: true)
        }
        let nav = UINavigationController(rootViewController: picker).then {
            $0.navigationBar.prefersLargeTitles = false
            $0.modalPresentationStyle = .formSheet
        }
        present(nav, animated: true)
    }

    func makeReceiveObject() -> ConfigurableObject {
        ConfigurableObject(
            icon: "square.and.arrow.down",
            title: "Receive Songs",
            explain: "Find another device on your network and import songs you don't have yet.",
            ephemeralAnnotation: .action { [weak self] _ in
                guard let self else {
                    return
                }
                navigationController?.pushViewController(
                    SyncReceiverViewController(environment: environment),
                    animated: true,
                )
            },
        )
    }
}
