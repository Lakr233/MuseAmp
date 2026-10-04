//
//  SettingsViewController+API.swift
//  MuseAmp
//
//  Created by @Lakr233 on 2026/04/11.
//

import AlertController
import ConfigurableKit
import UIKit

extension SettingsViewController {
    func makeServerConfigurationView() -> ConfigurableInfoView {
        let view = ConfigurableInfoView()
        view.configure(icon: .init(systemName: "server.rack"))
        view.configure(title: String(localized: "Server Profile"))
        refreshServerProfileView(view)
        serverProfileView = view
        view.use { [weak self] in
            guard let self else { return [] }

            var actions: [UIMenuElement] = [
                UIAction(
                    title: String(localized: "Import from File"),
                    image: UIImage(systemName: "doc"),
                ) { [weak self] _ in
                    self?.serverProfileImportCoordinator.presentImportPicker()
                },
                UIAction(
                    title: String(localized: "Read from Clipboard"),
                    image: UIImage(systemName: "doc.on.clipboard"),
                ) { [weak self] _ in
                    self?.presentPasteJSONPrompt()
                },
            ]

            if AppPreferences.currentSubsonicConfiguration != nil {
                actions.append(
                    UIAction(
                        title: String(localized: "Export Configuration"),
                        image: UIImage(systemName: "square.and.arrow.up"),
                    ) { [weak self] _ in
                        self?.exportServerConfiguration()
                    },
                )
                actions.append(
                    UIAction(
                        title: String(localized: "Delete Configuration"),
                        image: UIImage(systemName: "trash"),
                        attributes: .destructive,
                    ) { [weak self] _ in
                        self?.confirmClearServerProfile()
                    },
                )
            }

            return actions
        }
        return view
    }

    func refreshServerProfile() {
        refreshServerProfileView(serverProfileView)
    }
}

private extension SettingsViewController {
    var serverProfileDescription: String {
        guard let configuration = AppPreferences.currentSubsonicConfiguration else {
            return String(localized: "No Subsonic server profile is configured.")
        }

        return String(
            format: String(localized: "URL: %@\nUsername: %@\nPassword: %@"),
            AppPreferences.displayServerURL(for: configuration.baseURL),
            configuration.username,
            "••••••",
        )
    }

    var serverProfileValue: String {
        AppPreferences.currentSubsonicConfiguration == nil
            ? String(localized: "Not Configured")
            : String(localized: "Configured")
    }

    func refreshServerProfileView(_ view: ConfigurableInfoView?) {
        view?.configure(description: serverProfileDescription)
        view?.configure(value: serverProfileValue)
    }

    func presentPasteJSONPrompt() {
        let input = AlertInputViewController(
            title: "Paste JSON",
            message: "Paste a JSON object containing serverURL, username, and password.",
            placeholder: "{\"serverURL\":\"https://example.com/rest\",\"username\":\"demo\",\"password\":\"secret\"}",
            text: "",
        ) { [weak self] text in
            Task { @MainActor [weak self] in
                await self?.serverProfileImportCoordinator.importServerProfile(fromJSONText: text)
            }
        }
        present(input, animated: true)
    }

    func exportServerConfiguration() {
        serverProfileImportCoordinator.exportServerConfiguration()
    }

    func confirmClearServerProfile() {
        serverProfileImportCoordinator.confirmClearServerProfile()
    }
}
