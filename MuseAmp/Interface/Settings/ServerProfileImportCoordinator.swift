//
//  ServerProfileImportCoordinator.swift
//  MuseAmp
//
//  Created by OpenAI on 2026/04/15.
//

import AlertController
import UIKit
import UniformTypeIdentifiers

@MainActor
final class ServerProfileImportCoordinator: NSObject {
    private weak var viewController: UIViewController?
    private let onConfigurationChanged: @MainActor () -> Void
    private let validateConfiguration: @MainActor (SubsonicConfiguration) async throws -> Void

    init(
        viewController: UIViewController?,
        environment: AppEnvironment?,
        onConfigurationChanged: @escaping @MainActor () -> Void = {},
        validateConfiguration: (@MainActor (SubsonicConfiguration) async throws -> Void)? = nil,
    ) {
        self.viewController = viewController
        self.onConfigurationChanged = onConfigurationChanged
        self.validateConfiguration = validateConfiguration ?? { [weak environment] configuration in
            guard let environment else {
                throw ServerProfileImportFlowError.servicesUnavailable
            }

            let previousConfiguration = AppPreferences.currentSubsonicConfiguration
            AppPreferences.setSubsonicConfiguration(configuration)

            do {
                try await environment.apiClient.ping()
            } catch {
                if let previousConfiguration {
                    AppPreferences.setSubsonicConfiguration(previousConfiguration)
                } else {
                    AppPreferences.clearSubsonicConfiguration()
                }
                throw error
            }
        }
    }

    func presentImportPicker() {
        guard let viewController else {
            return
        }

        let subsonicType = UTType("wiki.qaq.museamp.subsonicconfig") ?? .json
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json, subsonicType])
        picker.delegate = self
        picker.allowsMultipleSelection = false
        viewController.present(picker, animated: true)
    }

    func presentImportConfirmation(forFileURL url: URL) {
        guard let viewController else {
            return
        }

        ConfirmationAlertPresenter.present(
            on: viewController,
            title: String(localized: "Server Profile"),
            message: String(localized: "Import this Subsonic server profile into Muse Amp?"),
            confirmTitle: String(localized: "Import"),
        ) { [weak self] in
            Task { @MainActor [weak self] in
                await self?.importServerProfile(fromFileURL: url)
            }
        }
    }

    func importServerProfile(fromJSONText text: String) async {
        do {
            let configuration = try parseServerProfile(from: Data(text.utf8))
            try await validateAndPersistServerProfile(configuration)
        } catch {
            presentServerProfileError(error)
        }
    }

    func importServerProfile(fromFileURL url: URL) async {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url)
            let configuration = try parseServerProfile(from: data)
            try await validateAndPersistServerProfile(configuration)
        } catch {
            presentServerProfileError(error)
        }
    }

    func parseServerProfile(from data: Data) throws -> SubsonicConfiguration {
        guard let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ServerProfileImportError.invalidJSON
        }

        let candidateObjects: [[String: Any]] = [
            jsonObject,
            jsonObject["subsonic"] as? [String: Any],
            jsonObject["profile"] as? [String: Any],
        ].compactMap(\.self)

        let serverValue = firstStringValue(
            for: ["serverurl", "server", "baseurl", "url", "host"],
            in: candidateObjects,
        )
        let username = firstStringValue(for: ["username", "user"], in: candidateObjects)
        let password = firstStringValue(for: ["password", "pass"], in: candidateObjects)

        guard let serverValue else {
            throw ServerProfileImportError.missingServerURL
        }
        guard let baseURL = AppPreferences.normalizeSubsonicServerURL(serverValue) else {
            throw ServerProfileImportError.invalidServerURL
        }
        guard let username else {
            throw ServerProfileImportError.missingUsername
        }
        guard let password else {
            throw ServerProfileImportError.missingPassword
        }

        return SubsonicConfiguration(baseURL: baseURL, username: username, password: password)
    }

    func exportServerConfiguration() {
        guard let viewController,
              let configuration = AppPreferences.currentSubsonicConfiguration
        else {
            return
        }

        do {
            let json: [String: Any] = [
                "subsonic": [
                    "serverURL": AppPreferences.displayServerURL(for: configuration.baseURL),
                    "username": configuration.username,
                    "password": configuration.password,
                ],
            ]
            let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])

            let tempDir = FileManager.default.temporaryDirectory
            let fileURL = tempDir.appendingPathComponent("server.subsonicconfig")
            try data.write(to: fileURL)

            let activityVC = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = viewController.view
                popover.sourceRect = viewController.view.bounds
            }
            viewController.present(activityVC, animated: true)
        } catch {
            presentServerProfileError(error)
        }
    }

    func confirmClearServerProfile() {
        guard let viewController else {
            return
        }

        ConfirmationAlertPresenter.present(
            on: viewController,
            title: String(localized: "Delete Configuration"),
            message: String(localized: "This will remove the saved server URL, username, and password from this device."),
            confirmTitle: String(localized: "Delete"),
        ) { [weak self] in
            self?.clearServerProfile()
        }
    }

    func clearServerProfile() {
        AppPreferences.clearSubsonicConfiguration()
        onConfigurationChanged()
        presentServerProfileAlert(
            title: String(localized: "Configuration Cleared"),
            message: String(localized: "The saved Subsonic server profile was removed."),
        )
    }
}

extension ServerProfileImportCoordinator: UIDocumentPickerDelegate {
    func documentPicker(_: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else {
            return
        }

        Task { @MainActor [weak self] in
            await self?.importServerProfile(fromFileURL: url)
        }
    }
}

private extension ServerProfileImportCoordinator {
    func firstStringValue(for keys: [String], in objects: [[String: Any]]) -> String? {
        for object in objects {
            let normalized = Dictionary(uniqueKeysWithValues: object.map { ($0.key.lowercased(), $0.value) })
            for key in keys {
                if let value = normalized[key] as? String {
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty == false {
                        return trimmed
                    }
                }
            }
        }
        return nil
    }

    func validateAndPersistServerProfile(_ configuration: SubsonicConfiguration) async throws {
        try await validateConfiguration(configuration)
        onConfigurationChanged()
        presentServerProfileAlert(
            title: String(localized: "Server Verified"),
            message: String(localized: "The Subsonic server profile was imported and verified."),
        )
    }

    func presentServerProfileError(_ error: Error) {
        presentServerProfileAlert(
            title: String(localized: "Import Failed"),
            message: error.localizedDescription,
        )
    }

    func presentServerProfileAlert(title: String, message: String) {
        guard let viewController else {
            return
        }

        let alert = AlertViewController(title: .init(title), message: .init(message)) { context in
            context.addAction(title: "OK", attribute: .accent) {
                context.dispose()
            }
        }
        viewController.present(alert, animated: true)
    }
}

private enum ServerProfileImportError: LocalizedError {
    case invalidJSON
    case missingServerURL
    case invalidServerURL
    case missingUsername
    case missingPassword

    var errorDescription: String? {
        switch self {
        case .invalidJSON:
            String(localized: "The imported file must contain a valid JSON object.")
        case .missingServerURL:
            String(localized: "The imported JSON must include a serverURL field.")
        case .invalidServerURL:
            String(localized: "The imported server URL is invalid.")
        case .missingUsername:
            String(localized: "The imported JSON must include a username field.")
        case .missingPassword:
            String(localized: "The imported JSON must include a password field.")
        }
    }
}

private enum ServerProfileImportFlowError: LocalizedError {
    case servicesUnavailable

    var errorDescription: String? {
        switch self {
        case .servicesUnavailable:
            String(localized: "Server profile import is unavailable because the app services are not ready.")
        }
    }
}
