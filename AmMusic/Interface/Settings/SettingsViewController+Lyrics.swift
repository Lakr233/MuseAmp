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
            annotation: .toggle
        )
    }
}
