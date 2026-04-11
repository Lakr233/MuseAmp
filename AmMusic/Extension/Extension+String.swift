//
//  Extension+String.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import Foundation

extension String {
    var sanitizedTrackTitle: String {
        guard AppPreferences.isCleanSongTitleEnabled else { return self }
        let trimmed = trimmingCharacters(in: .whitespaces)
        guard let lastChar = trimmed.last,
              lastChar == ")" || lastChar == "）"
        else { return self }
        let openBrackets: Set<Character> = ["(", "（"]
        guard let openIndex = trimmed.firstIndex(where: { openBrackets.contains($0) }) else {
            return self
        }
        let prefix = String(trimmed[..<openIndex]).trimmingCharacters(in: .whitespaces)
        guard !prefix.isEmpty else { return self }
        return prefix
    }
}
