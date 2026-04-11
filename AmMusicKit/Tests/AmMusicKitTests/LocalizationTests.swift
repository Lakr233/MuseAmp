//
//  LocalizationTests.swift
//  AmMusicKit
//
//  Created by @Lakr233 on 2026/04/11.
//

@testable import AmMusicKit
import Testing

struct LocalizationTests {
    @Test
    func `API error descriptions use localized defaults`() {
        #expect(
            APIError.invalidRequest.errorDescription
                == LocalizationTestSupport.currentLocalizedValue("The request could not be created."),
        )
        #expect(
            APIError.invalidResponse.errorDescription
                == LocalizationTestSupport.currentLocalizedValue("The server returned an invalid response."),
        )
        #expect(
            APIError.requestFailed(statusCode: 404).errorDescription
                == LocalizationTestSupport.currentLocalizedValue("The server returned HTTP %ld.")
                .replacingOccurrences(of: "%ld", with: "404"),
        )
    }

    @Test
    func `Search type titles use localized defaults`() {
        #expect(SearchType.song.title == LocalizationTestSupport.currentLocalizedValue("Songs"))
        #expect(SearchType.album.title == LocalizationTestSupport.currentLocalizedValue("Albums"))
        #expect(SearchType.artist.title == LocalizationTestSupport.currentLocalizedValue("Artists"))
    }

    @Test
    func `English localization resources stay stable`() {
        #expect(
            LocalizationTestSupport.localizedValue(
                "The request could not be created.",
                localization: "en",
            ) == "The request could not be created.",
        )
        #expect(LocalizationTestSupport.localizedValue("Songs", localization: "en") == "Songs")
        #expect(LocalizationTestSupport.localizedValue("Albums", localization: "en") == "Albums")
        #expect(LocalizationTestSupport.localizedValue("Artists", localization: "en") == "Artists")
    }

    @Test
    func `Chinese localization resources stay stable`() {
        #expect(
            LocalizationTestSupport.localizedValue(
                "The request could not be created.",
                localization: "zh-Hans",
            ) == "无法创建请求。",
        )
        #expect(LocalizationTestSupport.localizedValue("Songs", localization: "zh-Hans") == "歌曲")
        #expect(LocalizationTestSupport.localizedValue("Albums", localization: "zh-Hans") == "专辑")
        #expect(LocalizationTestSupport.localizedValue("Artists", localization: "zh-Hans") == "艺人")
    }
}
