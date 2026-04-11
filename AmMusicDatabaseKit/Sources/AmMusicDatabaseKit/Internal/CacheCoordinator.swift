//
//  CacheCoordinator.swift
//  AmMusicDatabaseKit
//
//  Created by @Lakr233 on 2026/04/11.
//

import Foundation

struct CacheCoordinator {
    let paths: LibraryPaths
    let lyricsStore: LyricsCacheStore
    let logger: DatabaseLogger

    func writeArtwork(data: Data, trackID: String) throws {
        let url = paths.artworkCacheURL(for: trackID)
        if FileManager.default.fileExists(atPath: url.path) { return }
        do {
            try data.write(to: url, options: .atomic)
            DBLog.verbose(logger, "CacheCoordinator", "writeArtwork trackID=\(trackID)")
        } catch {
            DBLog.error(logger, "CacheCoordinator", "writeArtwork failed trackID=\(trackID) error=\(error.localizedDescription)")
            throw error
        }
    }

    func writeLyrics(text: String, trackID: String) throws {
        try lyricsStore.saveLyrics(text, for: trackID)
    }

    func removeTrackCaches(trackID: String) {
        let artworkURL = paths.artworkCacheURL(for: trackID)
        if FileManager.default.fileExists(atPath: artworkURL.path) {
            try? FileManager.default.removeItem(at: artworkURL)
        }
        try? lyricsStore.removeLyrics(for: trackID)
    }

    func clearArtworkCache() {
        let directory = paths.artworkCacheDirectory
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        guard let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            DBLog.warning(logger, "CacheCoordinator", "clearArtworkCache failed to list directory")
            return
        }
        var removed = 0
        for url in urls where !url.hasDirectoryPath {
            do {
                try FileManager.default.removeItem(at: url)
                removed += 1
            } catch {
                DBLog.warning(logger, "CacheCoordinator", "clearArtworkCache failed to remove \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        DBLog.info(logger, "CacheCoordinator", "clearArtworkCache removed=\(removed)/\(urls.count)")
    }

    func pruneOrphanArtwork(validTrackIDs: Set<String>) throws -> [String] {
        try pruneOrphans(
            in: paths.artworkCacheDirectory,
            validTrackIDs: validTrackIDs,
            expectedExtension: "jpg",
        )
    }

    func pruneOrphanLyrics(validTrackIDs: Set<String>) throws -> [String] {
        try pruneOrphans(
            in: paths.lyricsCacheDirectory,
            validTrackIDs: validTrackIDs,
            expectedExtension: "lrc",
        )
    }

    func orphanArtworkTrackIDs(validTrackIDs: Set<String>) throws -> [String] {
        try orphanTrackIDs(
            in: paths.artworkCacheDirectory,
            validTrackIDs: validTrackIDs,
            expectedExtension: "jpg",
        )
    }

    func orphanLyricsTrackIDs(validTrackIDs: Set<String>) throws -> [String] {
        try orphanTrackIDs(
            in: paths.lyricsCacheDirectory,
            validTrackIDs: validTrackIDs,
            expectedExtension: "lrc",
        )
    }

    func countFiles(in directory: URL) -> Int {
        guard let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return 0
        }
        return urls.count(where: { !$0.hasDirectoryPath })
    }

    private func pruneOrphans(in directory: URL, validTrackIDs: Set<String>, expectedExtension: String) throws -> [String] {
        let trackIDs = try orphanTrackIDs(in: directory, validTrackIDs: validTrackIDs, expectedExtension: expectedExtension)
        for trackID in trackIDs {
            let fileURL = directory.appendingPathComponent("\(trackID).\(expectedExtension)", isDirectory: false)
            try FileManager.default.removeItem(at: fileURL)
        }
        return trackIDs
    }

    private func orphanTrackIDs(in directory: URL, validTrackIDs: Set<String>, expectedExtension: String) throws -> [String] {
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return []
        }
        let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        var trackIDs: [String] = []
        for url in urls where !url.hasDirectoryPath {
            guard url.pathExtension.lowercased() == expectedExtension else {
                continue
            }
            let trackID = url.deletingPathExtension().lastPathComponent
            guard !validTrackIDs.contains(trackID) else {
                continue
            }
            trackIDs.append(trackID)
        }
        return trackIDs
    }
}
