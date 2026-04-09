@testable import AmMusicKit
import Foundation

enum LocalizationTestSupport {
    static func localizedValue(_ key: String, localization: String) -> String {
        guard let path = Bundle.module.path(forResource: localization, ofType: "lproj"),
              let bundle = Bundle(path: path)
        else {
            fatalError("Missing localization bundle: \(localization)")
        }

        return bundle.localizedString(forKey: key, value: nil, table: "Localizable")
    }

    static func currentLocalizedValue(_ key: String) -> String {
        let localization = Bundle.module.preferredLocalizations.first
            ?? Bundle.module.developmentLocalization
            ?? "en"
        return localizedValue(key, localization: localization)
    }
}
