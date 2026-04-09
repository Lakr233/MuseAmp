import AmMusicDatabaseKit
import Foundation

extension String {
    nonisolated var isKnownAlbumID: Bool {
        !isEmpty && self != "unknown"
    }

    nonisolated var isCatalogID: Bool {
        !isEmpty && allSatisfy(\.isNumber)
    }
}

nonisolated func sanitizedLogText(_ text: String, maxLength: Int? = nil) -> String {
    let compact = text
        .components(separatedBy: .whitespacesAndNewlines)
        .filter { !$0.isEmpty }
        .joined(separator: " ")
        .replacingOccurrences(of: "\"", with: "'")

    guard let maxLength, compact.count > maxLength else {
        return compact
    }
    let endIndex = compact.index(compact.startIndex, offsetBy: maxLength)
    return compact[..<endIndex] + "..."
}
