import Foundation

enum LyricsChineseScriptConverter {
    enum SystemChineseScript {
        case simplified
        case traditional
        case none
    }

    static var systemChineseScript: SystemChineseScript {
        guard let preferred = Locale.preferredLanguages.first else {
            return .none
        }
        let locale = Locale(identifier: preferred)
        guard locale.language.languageCode?.identifier == "zh" else {
            return .none
        }
        let script = locale.language.script?.identifier
        if script == "Hant" {
            return .traditional
        }
        return .simplified
    }

    static func convertToSystemScript(_ text: String) -> String {
        let script = systemChineseScript
        guard script != .none else { return text }

        let transform: CFString = switch script {
        case .simplified: "Hant-Hans" as CFString
        case .traditional: "Hans-Hant" as CFString
        case .none: fatalError()
        }

        let mutable = NSMutableString(string: text)
        CFStringTransform(mutable, nil, transform, false)
        return mutable as String
    }
}
