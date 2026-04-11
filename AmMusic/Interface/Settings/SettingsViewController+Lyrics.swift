//
//  SettingsViewController+Lyrics.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import ConfigurableKit
import UIKit

extension SettingsViewController {
    func makeLyricsAutoConvertChineseObject() -> ConfigurableObject {
        ConfigurableObject(
            icon: "character.textbox",
            title: "Auto-Convert Chinese Script",
            explain: "Automatically convert lyrics between Simplified and Traditional Chinese to match your system language.",
            key: AppPreferences.lyricsAutoConvertChineseKey,
            defaultValue: false,
            annotation: .toggle,
        )
    }

    func makeCleanSongTitleObject() -> ConfigurableObject {
        ConfigurableObject(
            icon: "textformat.abc",
            title: "Clean Song Titles",
            explain: "Remove trailing parenthesized content from song names for a cleaner display.",
            key: AppPreferences.cleanSongTitleKey,
            defaultValue: false,
            annotation: .toggle,
        )
    }
}
