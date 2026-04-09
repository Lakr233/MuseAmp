import Foundation

struct LibraryFileManager {
    let paths: LibraryPaths
    let logger: DatabaseLogger

    func moveToLibrary(
        from sourceURL: URL,
        trackID: String,
        albumID: String,
        fileExtension: String
    ) throws -> (finalURL: URL, relativePath: String) {
        let safeExtension = sanitizePathComponent(fileExtension.nilIfEmpty ?? "m4a")
        let relativePath = "\(sanitizePathComponent(albumID))/\(sanitizePathComponent(trackID)).\(safeExtension)"
        let finalURL = paths.absoluteAudioURL(for: relativePath)
        let stagingURL = finalURL.deletingLastPathComponent()
            .appendingPathComponent(finalURL.lastPathComponent + ".tmp", isDirectory: false)

        do {
            try FileManager.default.createDirectory(
                at: finalURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
            if FileManager.default.fileExists(atPath: stagingURL.path) {
                try FileManager.default.removeItem(at: stagingURL)
            }
            if FileManager.default.fileExists(atPath: finalURL.path) {
                try FileManager.default.removeItem(at: finalURL)
            }
            try FileManager.default.moveItem(at: sourceURL, to: stagingURL)
            try FileManager.default.moveItem(at: stagingURL, to: finalURL)
            DBLog.info(logger, "LibraryFileManager", "moveToLibrary relativePath=\(relativePath)")
            return (finalURL, relativePath)
        } catch {
            DBLog.error(logger, "LibraryFileManager", "moveToLibrary failed trackID=\(trackID) error=\(error.localizedDescription)")
            throw error
        }
    }

    func removeTrackFile(relativePath: String) throws {
        let url = paths.absoluteAudioURL(for: relativePath)
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            try removeEmptyDirectoryIfNeeded(url.deletingLastPathComponent())
        } catch {
            DBLog.error(logger, "LibraryFileManager", "removeTrackFile failed relativePath=\(relativePath) error=\(error.localizedDescription)")
            throw error
        }
    }

    func removeAlbumDirectory(albumID: String) throws {
        let directory = paths.audioDirectory.appendingPathComponent(sanitizePathComponent(albumID), isDirectory: true)
        do {
            if FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.removeItem(at: directory)
            }
        } catch {
            DBLog.error(logger, "LibraryFileManager", "removeAlbumDirectory failed albumID=\(albumID) error=\(error.localizedDescription)")
            throw error
        }
    }

    func removeEmptyDirectoryIfNeeded(_ directory: URL) throws {
        guard directory.path != paths.audioDirectory.path else {
            return
        }
        let contents = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        guard contents.isEmpty else {
            return
        }
        try FileManager.default.removeItem(at: directory)
    }
}
