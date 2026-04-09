import ConfigurableKit
import Foundation

enum AppPreferences {
    nonisolated static let apiHostKey = "wiki.qaq.ammusic.settings.api-host"
    nonisolated static let apiAuthorizationKey = "wiki.qaq.ammusic.settings.api-authorization"
    nonisolated static let lyricsAutoConvertChineseKey = "wiki.qaq.ammusic.settings.lyrics-auto-convert-chinese"
    nonisolated static let defaultAPIBaseURL = URL(string: "https://example.com")!

    nonisolated static var defaultAPIHost: String {
        displayHost(for: defaultAPIBaseURL)
    }

    nonisolated static var configuredAPIHost: String {
        let value: String = ConfigurableKit.value(forKey: apiHostKey, defaultValue: "")
        return normalizeHost(value) ?? ""
    }

    nonisolated static var configuredAPIAuthorizationToken: String? {
        let value: String = ConfigurableKit.value(forKey: apiAuthorizationKey, defaultValue: "")
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    nonisolated static var isLyricsAutoConvertChineseEnabled: Bool {
        ConfigurableKit.value(forKey: lyricsAutoConvertChineseKey, defaultValue: false)
    }

    nonisolated static func effectiveAPIBaseURL(fallback: URL = defaultAPIBaseURL) -> URL {
        guard let host = normalizeHost(configuredAPIHost),
              let url = URL(string: "https://\(host)")
        else {
            return fallback
        }
        return url
    }

    nonisolated static func normalizeHost(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return nil
        }

        if let components = URLComponents(string: trimmed),
           let host = normalizedHost(from: components)
        {
            return host
        }

        guard let components = URLComponents(string: "https://\(trimmed)") else {
            return nil
        }
        return normalizedHost(from: components)
    }

    nonisolated static func displayHost(for url: URL) -> String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = normalizedHost(from: components)
        else {
            return url.host ?? url.absoluteString
        }
        return host
    }
}

extension AppPreferences {
    nonisolated static func normalizedHost(from components: URLComponents) -> String? {
        guard let host = components.host, host.isEmpty == false else {
            return nil
        }
        if let port = components.port {
            return "\(host):\(port)"
        }
        return host
    }
}
