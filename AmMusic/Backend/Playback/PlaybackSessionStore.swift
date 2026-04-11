//
//  PlaybackSessionStore.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import AmMusicPlayerKit
import Foundation

nonisolated struct PlaybackSessionStore {
    let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileURL: URL) {
        self.fileURL = fileURL
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func load() -> PersistedPlaybackSession? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            AppLog.verbose(self, "load no file at \(fileURL.lastPathComponent)")
            return nil
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let session = try decoder.decode(PersistedPlaybackSession.self, from: data)
            AppLog.info(self, "load restored session trackCount=\(session.queue.count) current=\(session.currentTrackID)")
            return session
        } catch {
            AppLog.error(self, "load failed error=\(error)")
            return nil
        }
    }

    func save(_ session: PersistedPlaybackSession) {
        do {
            let data = try encoder.encode(session)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil,
            )
            try data.write(to: fileURL, options: .atomic)
            AppLog.verbose(self, "save persisted trackCount=\(session.queue.count)")
        } catch {
            AppLog.error(self, "save failed error=\(error)")
        }
    }

    func clear() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }
        do {
            try FileManager.default.removeItem(at: fileURL)
            AppLog.info(self, "clear removed session file")
        } catch {
            AppLog.error(self, "clear failed error=\(error)")
        }
    }
}

nonisolated struct PersistedPlaybackSession: Codable {
    let queue: [PersistedPlaybackTrack]
    let currentTrackID: String
    let currentIndex: Int
    let currentTime: TimeInterval
    let shuffled: Bool
    let repeatMode: RepeatMode
    let source: PlaybackSource?
    let shouldResumePlayback: Bool
}

nonisolated struct PersistedPlaybackTrack: Codable {
    let id: String
    let title: String
    let artistName: String
    let albumName: String?
    let albumID: String?
    let artworkURL: String?
    let durationInSeconds: TimeInterval?
    let localRelativePath: String?
}
