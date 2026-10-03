//
//  LyricsCacheStore.swift
//  MuseAmpDatabaseKit
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
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        } catch {
            logger.warning("LyricsCacheStore", "lyrics read failed trackID=\(trackID) error=\(error.localizedDescription)")
            return nil
        }
    }

    public func saveLyrics(_ lyrics: String, for trackID: String) throws {
        let url = paths.lyricsCacheURL(for: trackID)
        do {
            try lyrics.write(to: url, atomically: true, encoding: .utf8)
            logger.verbose("LyricsCacheStore", "saveLyrics trackID=\(trackID) length=\(lyrics.count)")
        } catch {
            logger.error("LyricsCacheStore", "saveLyrics failed trackID=\(trackID) error=\(error.localizedDescription)")
            throw error
        }
    }

    public func removeLyrics(for trackID: String) throws {
        let url = paths.lyricsCacheURL(for: trackID)
        do {
            try FileManager.default.removeItem(at: url)
            logger.verbose("LyricsCacheStore", "removeLyrics trackID=\(trackID)")
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileNoSuchFileError {
            return
        } catch {
            logger.error("LyricsCacheStore", "removeLyrics failed trackID=\(trackID) error=\(error.localizedDescription)")
            throw error
        }
    }
}
