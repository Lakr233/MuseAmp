//
//  AppPreferences.swift
//  MuseAmp
//
//  Created by @Lakr233 on 2026/04/11.
//

#if canImport(ConfigurableKit)
    import ConfigurableKit
#endif
import Foundation

struct SubsonicConfiguration: Equatable, Sendable {
    let baseURL: URL
    let username: String
    let password: String
}

enum AppPreferences {
    nonisolated static let subsonicServerURLKey = "wiki.qaq.museamp.settings.subsonic-server-url"
    nonisolated static let subsonicUsernameKey = "wiki.qaq.museamp.settings.subsonic-username"
    nonisolated static let subsonicPasswordKey = "wiki.qaq.museamp.settings.subsonic-password"
    nonisolated static let lyricsAutoConvertChineseKey = "wiki.qaq.museamp.settings.lyrics-auto-convert-chinese"
    nonisolated static let cleanSongTitleKey = "wiki.qaq.museamp.settings.clean-song-title"
    nonisolated static let maxConcurrentDownloadsKey = "wiki.qaq.museamp.settings.max-concurrent-downloads"
    nonisolated static let libraryAlbumSortOptionKey = "wiki.qaq.museamp.sort.library-albums"
    nonisolated static let songsSortOptionKey = "wiki.qaq.museamp.sort.songs"
    nonisolated static let playlistsSortOptionKey = "wiki.qaq.museamp.sort.playlists"
    nonisolated static let defaultAPIBaseURL = URL(string: "https://example.com/rest")!

    nonisolated static var configuredSubsonicServerURL: URL? {
        #if canImport(ConfigurableKit)
            let value: String = ConfigurableKit.value(forKey: subsonicServerURLKey, defaultValue: "")
            return normalizeSubsonicServerURL(value)
        #else
            nil
        #endif
    }

    nonisolated static var configuredSubsonicUsername: String {
        #if canImport(ConfigurableKit)
            let value: String = ConfigurableKit.value(forKey: subsonicUsernameKey, defaultValue: "")
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        #else
            ""
        #endif
    }

    nonisolated static var configuredSubsonicPassword: String {
        #if canImport(ConfigurableKit)
            let value: String = ConfigurableKit.value(forKey: subsonicPasswordKey, defaultValue: "")
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        #else
            ""
        #endif
    }

    nonisolated static var currentSubsonicConfiguration: SubsonicConfiguration? {
        guard let baseURL = configuredSubsonicServerURL else {
            return nil
        }

        let username = configuredSubsonicUsername
        let password = configuredSubsonicPassword
        guard username.isEmpty == false, password.isEmpty == false else {
            return nil
        }

        return SubsonicConfiguration(
            baseURL: baseURL,
            username: username,
            password: password,
        )
    }

    nonisolated static var isLyricsAutoConvertChineseEnabled: Bool {
        #if canImport(ConfigurableKit)
            ConfigurableKit.value(forKey: lyricsAutoConvertChineseKey, defaultValue: false)
        #else
            false
        #endif
    }

    nonisolated static var isCleanSongTitleEnabled: Bool {
        #if canImport(ConfigurableKit)
            ConfigurableKit.value(forKey: cleanSongTitleKey, defaultValue: false)
        #else
            false
        #endif
    }

    nonisolated static var maxConcurrentDownloads: Int {
        #if canImport(ConfigurableKit)
            let value: Int = ConfigurableKit.value(forKey: maxConcurrentDownloadsKey, defaultValue: 1)
            return max(1, min(value, 8))
        #else
            1
        #endif
    }

    nonisolated static func normalizeSubsonicServerURL(_ input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return nil
        }

        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard var components = URLComponents(string: candidate) else {
            return nil
        }
        guard components.host?.isEmpty == false else {
            return nil
        }

        components.query = nil
        components.fragment = nil

        let normalizedPath: String = if components.path.isEmpty || components.path == "/" {
            "/rest"
        } else {
            components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        }
        components.path = normalizedPath.hasSuffix("/rest") ? normalizedPath : normalizedPath + "/rest"

        return components.url
    }

    nonisolated static func displayServerURL(for url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        components.query = nil
        components.fragment = nil
        return components.url?.absoluteString ?? url.absoluteString
    }

    nonisolated static func setSubsonicConfiguration(_ configuration: SubsonicConfiguration) {
        #if canImport(ConfigurableKit)
            ConfigurableKit.set(
                value: displayServerURL(for: configuration.baseURL),
                forKey: subsonicServerURLKey,
            )
            ConfigurableKit.set(value: configuration.username, forKey: subsonicUsernameKey)
            ConfigurableKit.set(value: configuration.password, forKey: subsonicPasswordKey)
        #endif
        NotificationCenter.default.post(name: .serverConfigurationDidChange, object: nil)
    }

    nonisolated static func clearSubsonicConfiguration() {
        #if canImport(ConfigurableKit)
            ConfigurableKit.set(value: "", forKey: subsonicServerURLKey)
            ConfigurableKit.set(value: "", forKey: subsonicUsernameKey)
            ConfigurableKit.set(value: "", forKey: subsonicPasswordKey)
        #endif
        NotificationCenter.default.post(name: .serverConfigurationDidChange, object: nil)
    }

    nonisolated static func storedSortOption<T: RawRepresentable>(
        forKey key: String,
        defaultValue: T,
    ) -> T where T.RawValue == String {
        guard let storedValue = UserDefaults.standard.string(forKey: key),
              let option = T(rawValue: storedValue)
        else {
            return defaultValue
        }
        return option
    }

    nonisolated static func setStoredSortOption<T: RawRepresentable>(
        _ option: T,
        forKey key: String,
    ) where T.RawValue == String {
        UserDefaults.standard.set(option.rawValue, forKey: key)
    }
}
