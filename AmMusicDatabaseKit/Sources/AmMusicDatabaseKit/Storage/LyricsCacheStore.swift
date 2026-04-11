//
//  LyricsCacheStore.swift
//  AmMusicDatabaseKit
//
//  Created by @Lakr233 on 2026/04/11.
//

import Foundation

public struct LyricsCacheStore: Sendable {
    public let paths: LibraryPaths
    private let logger: DatabaseLogger

    public init(paths: LibraryPaths, logSink: LogSink? = nil) {
        self.paths = paths
        logger = DatabaseLogger(sink: logSink)
    }

    public func lyrics(for trackID: String) -> String? {
        do {
            return try String(contentsOf: paths.lyricsCacheURL(for: trackID), encoding: .utf8)
        } catch {
            DBLog.warning(logger, "LyricsCacheStore", "lyrics read failed trackID=\(trackID) error=\(error.localizedDescription)")
            return nil
        }
    }

    public func saveLyrics(_ lyrics: String, for trackID: String) throws {
        let url = paths.lyricsCacheURL(for: trackID)
        do {
            try lyrics.write(to: url, atomically: true, encoding: .utf8)
            DBLog.verbose(logger, "LyricsCacheStore", "saveLyrics trackID=\(trackID) length=\(lyrics.count)")
        } catch {
            DBLog.error(logger, "LyricsCacheStore", "saveLyrics failed trackID=\(trackID) error=\(error.localizedDescription)")
            throw error
        }
    }

    public func removeLyrics(for trackID: String) throws {
        let url = paths.lyricsCacheURL(for: trackID)
        do {
            try FileManager.default.removeItem(at: url)
            DBLog.verbose(logger, "LyricsCacheStore", "removeLyrics trackID=\(trackID)")
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileNoSuchFileError {
            return
        } catch {
            DBLog.error(logger, "LyricsCacheStore", "removeLyrics failed trackID=\(trackID) error=\(error.localizedDescription)")
            throw error
        }
    }

    public func removeLyrics(for trackIDs: [String]) throws {
        for trackID in trackIDs {
            try removeLyrics(for: trackID)
        }
    }

    public func removeAllLyrics() throws {
        do {
            if FileManager.default.fileExists(atPath: paths.lyricsCacheDirectory.path) {
                try FileManager.default.removeItem(at: paths.lyricsCacheDirectory)
            }
            try FileManager.default.createDirectory(
                at: paths.lyricsCacheDirectory,
                withIntermediateDirectories: true,
                attributes: nil,
            )
            DBLog.info(logger, "LyricsCacheStore", "removeAllLyrics")
        } catch {
            DBLog.error(logger, "LyricsCacheStore", "removeAllLyrics failed error=\(error.localizedDescription)")
            throw error
        }
    }
}
