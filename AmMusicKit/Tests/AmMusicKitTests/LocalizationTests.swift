@testable import AmMusicKit
import Testing

struct LocalizationTests {
    @Test("API error descriptions use localized defaults")
    func apiErrorDescriptions() {
        #expect(
            APIError.invalidRequest.errorDescription
                == LocalizationTestSupport.currentLocalizedValue("The request could not be created.")
        )
        #expect(
            APIError.invalidResponse.errorDescription
                == LocalizationTestSupport.currentLocalizedValue("The server returned an invalid response.")
        )
        #expect(
            APIError.requestFailed(statusCode: 404).errorDescription
                == LocalizationTestSupport.currentLocalizedValue("The server returned HTTP %ld.")
                .replacingOccurrences(of: "%ld", with: "404")
        )
    }

    @Test("Search type titles use localized defaults")
    func searchTypeTitles() {
        #expect(SearchType.song.title == LocalizationTestSupport.currentLocalizedValue("Songs"))
        #expect(SearchType.album.title == LocalizationTestSupport.currentLocalizedValue("Albums"))
        #expect(SearchType.artist.title == LocalizationTestSupport.currentLocalizedValue("Artists"))
    }

    @Test("English localization resources stay stable")
    func englishLocalizationResources() {
        #expect(
            LocalizationTestSupport.localizedValue(
                "The request could not be created.",
                localization: "en"
            ) == "The request could not be created."
        )
        #expect(LocalizationTestSupport.localizedValue("Songs", localization: "en") == "Songs")
        #expect(LocalizationTestSupport.localizedValue("Albums", localization: "en") == "Albums")
        #expect(LocalizationTestSupport.localizedValue("Artists", localization: "en") == "Artists")
    }

    @Test("Chinese localization resources stay stable")
    func chineseLocalizationResources() {
        #expect(
            LocalizationTestSupport.localizedValue(
                "The request could not be created.",
                localization: "zh-Hans"
            ) == "无法创建请求。"
        )
        #expect(LocalizationTestSupport.localizedValue("Songs", localization: "zh-Hans") == "歌曲")
        #expect(LocalizationTestSupport.localizedValue("Albums", localization: "zh-Hans") == "专辑")
        #expect(LocalizationTestSupport.localizedValue("Artists", localization: "zh-Hans") == "艺人")
    }
}
