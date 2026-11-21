//
//  Extension+Array.swift
//  MuseAmp
//
//  Created by @Lakr233 on 2026/11/21.
//

import Foundation

extension [String] {
    /// Joins short metadata pieces (artist, album, song count, status) for a
    /// row subtitle with the language's own comma: "Artist, Album" in English,
    /// "歌手，专辑" in Chinese. Empty pieces are skipped.
    nonisolated var joinedForDisplay: String {
        let parts = filter { !$0.isEmpty }
        guard var result = parts.first else { return "" }
        for part in parts.dropFirst() {
            result = String(localized: "\(result), \(part)")
        }
        return result
    }
}
