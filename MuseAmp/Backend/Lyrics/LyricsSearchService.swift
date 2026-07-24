//
//  LyricsSearchService.swift
//  MuseAmp
//
//  Created by qaq on 2/7/2026.
//

import Foundation
import MuseAmpDatabaseKit

/// Searches the local library by lyric content. Lyric text only exists as
/// cached `.lrc` files (imported embedded lyrics or fetched lyrics of
/// downloaded tracks), so this scans those files; remote catalog search
/// cannot match lyric bodies.
final class LyricsSearchService {
    struct Match: Sendable {
        let track: AudioTrackRecord
        let matchedLine: String
    }

    private let database: MusicLibraryDatabase
    private let lyricsCacheStore: LyricsCacheStore

    init(database: MusicLibraryDatabase, lyricsCacheStore: LyricsCacheStore) {
        self.database = database
        self.lyricsCacheStore = lyricsCacheStore
    }

    func search(query: String, limit: Int) async -> [Match] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty, limit > 0 else { return [] }

        let tracks: [AudioTrackRecord]
        do {
            tracks = try database.allTracks()
        } catch {
            AppLog.error(self, "search failed to load tracks error=\(error)")
            return []
        }

        let store = lyricsCacheStore
        let matches = await Task.detached(priority: .userInitiated) {
            var collected: [Match] = []
            for track in tracks {
                let lyricsURL = store.paths.lyricsCacheURL(for: track.trackID)
                guard FileManager.default.fileExists(atPath: lyricsURL.path) else { continue }
                guard let lyricsText = store.lyrics(for: track.trackID) else { continue }
                guard let line = Self.firstMatchingLine(in: lyricsText, needle: needle) else { continue }
                collected.append(Match(track: track, matchedLine: line))
                if collected.count >= limit {
                    break
                }
            }
            return collected
        }.value

        AppLog.info(self, "search query length=\(needle.count) scanned=\(tracks.count) matches=\(matches.count)")
        return matches
    }

    nonisolated static func firstMatchingLine(in lyricsText: String, needle: String) -> String? {
        for rawLine in lyricsText.components(separatedBy: .newlines) {
            let plain = plainLyricLine(rawLine)
            guard !plain.isEmpty else { continue }
            if plain.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
                return plain
            }
        }
        return nil
    }

    /// Strips leading LRC tags (`[mm:ss.xx]`, `[offset:...]`, …) so metadata
    /// tags never match and returned lines are display-ready.
    nonisolated static func plainLyricLine(_ line: String) -> String {
        var remainder = Substring(line)
        while remainder.first == "[", let close = remainder.firstIndex(of: "]") {
            remainder = remainder[remainder.index(after: close)...]
        }
        return remainder.trimmingCharacters(in: .whitespaces)
    }
}
