//
//  SettingsViewController+API.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import AlertController
import ConfigurableKit
import UIKit

extension SettingsViewController {
    func makeAPIEndpointView() -> ConfigurableInfoView {
        let view = ConfigurableInfoView()
        view.configure(icon: .init(systemName: "server.rack"))
        view.configure(title: String(localized: "API Endpoint"))
        view.configure(
            description: String(localized: "Enter the API host name. HTTPS is enforced automatically."),
        )
        view.configure(value: currentAPIEndpointValue)
        view.use { [weak self, weak view] in
            guard let self, let view else { return [] }
            return buildAPIEndpointMenu(view: view)
        }
        return view
    }

    func makeAuthorizationView() -> ConfigurableInfoView {
        let view = ConfigurableInfoView()
        view.configure(icon: .init(systemName: "lock"))
        view.configure(title: String(localized: "Authorization"))
        view.configure(
            description: String(localized: "Enter the token used for Authorization: Bearer <token>."),
        )
        view.configure(value: currentAuthorizationValue)
        view.use { [weak self, weak view] in
            guard let self, let view else { return [] }
            return buildAuthorizationMenu(view: view)
        }
        return view
    }

    func makeClearAPICacheObject() -> ConfigurableObject {
        ConfigurableObject(
            icon: "externaldrive.badge.xmark",
            title: "Clear API Cache",
            explain: "Remove all cached 2xx API responses and force fresh network fetches.",
            ephemeralAnnotation: .action { [weak self] _ in
                guard let self else { return }
                confirmClearAPICache()
            },
        )
    }
}

private extension SettingsViewController {
    var currentAPIEndpointValue: String {
        let host = AppPreferences.configuredAPIHost
        return host.isEmpty ? AppPreferences.defaultAPIHost : host
    }

    var currentAuthorizationValue: String {
        AppPreferences.configuredAPIAuthorizationToken == nil ? String(localized: "Not Configured") : String(localized: "Configured")
    }

    func buildAPIEndpointMenu(view: ConfigurableInfoView) -> [UIMenuElement] {
        let currentValue = AppPreferences.configuredAPIHost

        let editAction = UIAction(
            title: String(localized: "Edit"),
            image: UIImage(systemName: "character.cursor.ibeam"),
        ) { [weak self, weak view] _ in
            guard let self, let view else { return }
            let input = AlertInputViewController(
                title: String(localized: "Edit API Endpoint"),
                message: String(localized: "Enter a host name. HTTPS is enforced automatically."),
                placeholder: AppPreferences.defaultAPIHost,
                text: currentValue,
            ) { [weak view] newValue in
                let normalized = AppPreferences.normalizeHost(newValue) ?? ""
                ConfigurableKit.set(value: normalized, forKey: AppPreferences.apiHostKey)
                view?.configure(
                    value: normalized.isEmpty ? AppPreferences.defaultAPIHost : normalized,
                )
            }
            present(input, animated: true)
        }

        var menuElements: [UIMenuElement] = [editAction]

        if !currentValue.isEmpty {
            let copyAction = UIAction(
                title: String(localized: "Copy"),
                image: UIImage(systemName: "doc.on.doc"),
            ) { _ in
                UIPasteboard.general.string = currentValue
            }
            menuElements.append(copyAction)
        }

        let useDefaultAction = UIAction(
            title: String(format: String(localized: "Use Default (%@)"), AppPreferences.defaultAPIHost),
            image: UIImage(systemName: "arrow.counterclockwise"),
        ) { [weak view] _ in
            ConfigurableKit.set(value: "", forKey: AppPreferences.apiHostKey)
            view?.configure(value: AppPreferences.defaultAPIHost)
        }
        menuElements.append(UIMenu(options: .displayInline, children: [useDefaultAction]))

        return menuElements
    }

    func buildAuthorizationMenu(view: ConfigurableInfoView) -> [UIMenuElement] {
        let currentToken = AppPreferences.configuredAPIAuthorizationToken ?? ""

        let editAction = UIAction(
            title: String(localized: "Edit"),
            image: UIImage(systemName: "character.cursor.ibeam"),
        ) { [weak self, weak view] _ in
            guard let self, let view else { return }
            let input = AlertInputViewController(
                title: String(localized: "Edit Authorization"),
                message: String(localized: "Enter the token for Authorization: Bearer <token>."),
                placeholder: "token",
                text: currentToken,
            ) { [weak view] newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                ConfigurableKit.set(value: trimmed, forKey: AppPreferences.apiAuthorizationKey)
                view?.configure(value: trimmed.isEmpty ? String(localized: "Not Configured") : String(localized: "Configured"))
            }
            present(input, animated: true)
        }

        var menuElements: [UIMenuElement] = [editAction]

        if !currentToken.isEmpty {
            let copyAction = UIAction(
                title: String(localized: "Copy"),
                image: UIImage(systemName: "doc.on.doc"),
            ) { _ in
                UIPasteboard.general.string = currentToken
            }
            let clearAction = UIAction(
                title: String(localized: "Clear"),
                image: UIImage(systemName: "xmark.circle"),
            ) { [weak view] _ in
                ConfigurableKit.set(value: "", forKey: AppPreferences.apiAuthorizationKey)
                view?.configure(value: String(localized: "Not Configured"))
            }
            menuElements.append(contentsOf: [copyAction, clearAction])
        }

        return menuElements
    }
}
