@testable import AmMusic
import ConfigurableKit
import Foundation
import Testing

@Suite(.serialized)
struct AppPreferencesTests {
    @Test("Normalize host strips scheme path and query")
    func normalizeHost() {
        #expect(AppPreferences.normalizeHost("https://example.com/search?q=test") == "example.com")
        #expect(AppPreferences.normalizeHost("example.com:8443") == "example.com:8443")
        #expect(AppPreferences.normalizeHost("   ") == nil)
    }

    @Test("Authorization token trims surrounding whitespace")
    func authorizationTokenTrimming() {
        clearPreferences()
        defer { clearPreferences() }

        ConfigurableKit.set(value: "  test-token  ", forKey: AppPreferences.apiAuthorizationKey)

        #expect(AppPreferences.configuredAPIAuthorizationToken == "test-token")
    }

    @Test("APIClient picks up updated configured host")
    func apiClientUsesConfiguredHost() throws {
        clearPreferences()
        defer { clearPreferences() }

        let fallbackURL = try #require(URL(string: "https://fallback.example.com"))
        let client = APIClient(baseURL: fallbackURL)

        #expect(client.baseURL.host == "fallback.example.com")

        ConfigurableKit.set(value: "custom.example.com", forKey: AppPreferences.apiHostKey)

        #expect(client.baseURL.host == "custom.example.com")

        ConfigurableKit.set(value: "", forKey: AppPreferences.apiHostKey)

        #expect(client.baseURL.host == "fallback.example.com")
    }
}

private extension AppPreferencesTests {
    func clearPreferences() {
        UserDefaults.standard.removeObject(forKey: AppPreferences.apiHostKey)
        UserDefaults.standard.removeObject(forKey: AppPreferences.apiAuthorizationKey)
    }
}
