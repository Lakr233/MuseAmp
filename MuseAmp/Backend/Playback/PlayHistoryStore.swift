//
//  PlayHistoryStore.swift
//  MuseAmp
//
//  Created by @Lakr233 on 2026/11/20.
//

import Foundation

nonisolated struct PlayHistoryEntry: Codable, Equatable, Sendable {
    let trackID: String
    var albumID: String?
    var lastPlayedAt: Date
    var playCount: Int
}

/// Keeps when each song was last played, on this device only. The file lives
/// next to the saved playback state, which is excluded from backups and is
/// never part of a transfer.
@MainActor
final class PlayHistoryStore {
    nonisolated static let qualifyingPlaySeconds: TimeInterval = 30

    let fileURL: URL
    private(set) var entries: [String: PlayHistoryEntry]

    init(fileURL: URL) {
        self.fileURL = fileURL
        entries = Self.load(from: fileURL)
    }

    var isEmpty: Bool {
        entries.isEmpty
    }

    /// A play counts once its listened time passes 30 seconds or reaches half
    /// of the song, whichever comes first.
    nonisolated static func countsAsPlayed(listenedSeconds: TimeInterval, duration: TimeInterval) -> Bool {
        if listenedSeconds > qualifyingPlaySeconds {
            return true
        }
        guard duration.isFinite, duration > 0 else {
            return false
        }
        return !(listenedSeconds < duration / 2)
    }

    func recordPlay(trackID: String, albumID: String?, at date: Date = Date()) {
        guard !trackID.isEmpty else {
            return
        }
        var entry = entries[trackID] ?? PlayHistoryEntry(
            trackID: trackID,
            albumID: albumID,
            lastPlayedAt: date,
            playCount: 0,
        )
        if let albumID, !albumID.isEmpty {
            entry.albumID = albumID
        }
        entry.lastPlayedAt = date
        entry.playCount += 1
        entries[trackID] = entry
        AppLog.info(self, "recordPlay trackID=\(trackID) playCount=\(entry.playCount)")
        save()
        NotificationCenter.default.post(name: .playHistoryDidChange, object: self)
    }

    func lastPlayedDate(forTrackID trackID: String) -> Date? {
        entries[trackID]?.lastPlayedAt
    }

    /// The latest play of any song in each album.
    func albumLastPlayedDates() -> [String: Date] {
        var result: [String: Date] = [:]
        for entry in entries.values {
            guard let albumID = entry.albumID, !albumID.isEmpty else {
                continue
            }
            if let existing = result[albumID], !(existing < entry.lastPlayedAt) {
                continue
            }
            result[albumID] = entry.lastPlayedAt
        }
        return result
    }

    func clear() {
        entries.removeAll()
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                try FileManager.default.removeItem(at: fileURL)
            } catch {
                AppLog.error(self, "clear remove failed error=\(error)")
            }
        }
        AppLog.info(self, "clear removed play history")
        NotificationCenter.default.post(name: .playHistoryDidChange, object: self)
    }

    /// Played items first, most recent first; items never played keep the
    /// order they arrived in, after every played one.
    nonisolated static func sortedByRecentlyPlayed<Item>(
        _ items: [Item],
        lastPlayedAt: (Item) -> Date?,
    ) -> [Item] {
        var played: [(offset: Int, interval: TimeInterval, item: Item)] = []
        var neverPlayed: [Item] = []
        for (offset, item) in items.enumerated() {
            if let date = lastPlayedAt(item) {
                played.append((offset, date.timeIntervalSinceReferenceDate, item))
            } else {
                neverPlayed.append(item)
            }
        }
        played.sort { lhs, rhs in
            if lhs.interval != rhs.interval {
                return lhs.interval > rhs.interval
            }
            return lhs.offset < rhs.offset
        }
        return played.map(\.item) + neverPlayed
    }

    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(Array(entries.values).sorted { $0.trackID < $1.trackID })
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil,
            )
            try data.write(to: fileURL, options: .atomic)
        } catch {
            AppLog.error(self, "save failed error=\(error)")
        }
    }

    private static func load(from fileURL: URL) -> [String: PlayHistoryEntry] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return [:]
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let list = try JSONDecoder().decode([PlayHistoryEntry].self, from: data)
            return Dictionary(list.map { ($0.trackID, $0) }) { lhs, rhs in
                lhs.lastPlayedAt < rhs.lastPlayedAt ? rhs : lhs
            }
        } catch {
            AppLog.error("PlayHistoryStore", "load failed error=\(error)")
            return [:]
        }
    }
}
