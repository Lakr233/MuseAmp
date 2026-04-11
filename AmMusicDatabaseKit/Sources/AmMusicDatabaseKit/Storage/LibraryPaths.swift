//
//  LibraryPaths.swift
//  AmMusicDatabaseKit
//
//  Created by @Lakr233 on 2026/04/11.
//

import Foundation

public struct LibraryPaths: Sendable {
    public let baseDirectory: URL
    private let cacheRootDirectory: URL
    private let logger: DatabaseLogger

    public var audioDirectory: URL {
        baseDirectory.appendingPathComponent("Audio", isDirectory: true)
    }

    public var incomingDirectory: URL {
        baseDirectory.appendingPathComponent("Incoming", isDirectory: true)
    }

    public var databaseDirectory: URL {
        baseDirectory.appendingPathComponent("Database", isDirectory: true)
    }

    public var logsDirectory: URL {
        baseDirectory.appendingPathComponent("Logs", isDirectory: true)
    }

    public var indexDatabaseURL: URL {
        databaseDirectory.appendingPathComponent("library_index.sqlite", isDirectory: false)
    }

    public var stateDatabaseURL: URL {
        databaseDirectory.appendingPathComponent("library_state.sqlite", isDirectory: false)
    }

    public var artworkCacheDirectory: URL {
        cacheRootDirectory.appendingPathComponent("LibraryArtwork", isDirectory: true)
    }

    public var lyricsCacheDirectory: URL {
        baseDirectory.appendingPathComponent("LibraryLyrics", isDirectory: true)
    }

    public var legacyPlaylistURL: URL {
        baseDirectory.appendingPathComponent("playlists.json", isDirectory: false)
    }

    public var playbackStateURL: URL {
        baseDirectory.appendingPathComponent("playback-state.json", isDirectory: false)
    }

    public init(baseDirectory: URL? = nil, logSink: LogSink? = nil) {
        logger = DatabaseLogger(sink: logSink)
        if let baseDirectory {
            self.baseDirectory = baseDirectory
            cacheRootDirectory = baseDirectory.appendingPathComponent("Caches", isDirectory: true)
        } else {
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            self.baseDirectory = documents.appendingPathComponent("OfflineLibrary", isDirectory: true)
            let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            cacheRootDirectory = caches.appendingPathComponent("OfflineLibrary", isDirectory: true)
            Self.migrateFromApplicationSupportIfNeeded(to: self.baseDirectory, logger: logger)
        }
    }

    public func artworkCacheURL(for trackID: String) -> URL {
        artworkCacheDirectory.appendingPathComponent("\(sanitizePathComponent(trackID)).jpg", isDirectory: false)
    }

    public func lyricsCacheURL(for trackID: String) -> URL {
        lyricsCacheDirectory.appendingPathComponent("\(sanitizePathComponent(trackID)).lrc", isDirectory: false)
    }

    public func absoluteAudioURL(for relativePath: String) -> URL {
        audioDirectory.appendingPathComponent(relativePath, isDirectory: false)
    }

    public func relativeAudioPath(for fileURL: URL) -> String {
        let audioRoot = audioDirectory.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        guard filePath.hasPrefix(audioRoot) else {
            return fileURL.lastPathComponent
        }

        let suffix = filePath.dropFirst(audioRoot.count)
        return suffix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    public func inferredRelativePath(for trackID: String, albumID: String = "unknown", fileExtension: String = "m4a") -> String {
        let folder = sanitizePathComponent(albumID)
        let file = sanitizePathComponent(trackID) + "." + sanitizePathComponent(fileExtension)
        return "\(folder)/\(file)"
    }

    public func ensureDirectoriesExist() throws {
        migrateLegacyCacheDirectoriesIfNeeded()
        let directories = [
            baseDirectory,
            audioDirectory,
            incomingDirectory,
            databaseDirectory,
            logsDirectory,
            artworkCacheDirectory,
            lyricsCacheDirectory,
        ]

        for directory in directories {
            do {
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true,
                    attributes: nil,
                )
            } catch {
                DBLog.error(logger, "LibraryPaths", "createDirectory failed path=\(directory.path) error=\(error.localizedDescription)")
                throw error
            }
        }
    }

    private static func migrateFromApplicationSupportIfNeeded(to newBase: URL, logger: DatabaseLogger) {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
        ).first else {
            return
        }

        let oldBase = appSupport.appendingPathComponent("OfflineLibrary", isDirectory: true)
        guard FileManager.default.fileExists(atPath: oldBase.path) else {
            return
        }

        guard !FileManager.default.fileExists(atPath: newBase.path) else {
            try? FileManager.default.removeItem(at: oldBase)
            DBLog.info(logger, "LibraryPaths", "Application Support migration skipped because new base already exists")
            return
        }

        do {
            try FileManager.default.createDirectory(
                at: newBase.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil,
            )
            try FileManager.default.moveItem(at: oldBase, to: newBase)
            DBLog.info(logger, "LibraryPaths", "Migrated OfflineLibrary from Application Support")
        } catch {
            DBLog.error(logger, "LibraryPaths", "Application Support migration failed error=\(error.localizedDescription)")
        }
    }

    private func migrateLegacyCacheDirectoriesIfNeeded() {
        let migrations: [(from: URL, to: URL)] = [
            (
                baseDirectory.appendingPathComponent("ArtworkCache", isDirectory: true),
                artworkCacheDirectory,
            ),
            (
                baseDirectory.appendingPathComponent("LyricsCache", isDirectory: true),
                lyricsCacheDirectory,
            ),
        ]

        for migration in migrations {
            guard FileManager.default.fileExists(atPath: migration.from.path) else {
                continue
            }
            guard !FileManager.default.fileExists(atPath: migration.to.path) else {
                continue
            }

            do {
                try FileManager.default.createDirectory(
                    at: migration.to.deletingLastPathComponent(),
                    withIntermediateDirectories: true,
                    attributes: nil,
                )
                try FileManager.default.moveItem(at: migration.from, to: migration.to)
                DBLog.info(logger, "LibraryPaths", "Migrated legacy directory from \(migration.from.lastPathComponent)")
            } catch {
                DBLog.error(logger, "LibraryPaths", "Legacy directory migration failed source=\(migration.from.path) error=\(error.localizedDescription)")
            }
        }
    }
}
