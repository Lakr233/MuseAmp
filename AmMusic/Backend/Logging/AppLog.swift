import AmMusicDatabaseKit
import Dog
import Foundation

nonisolated enum AppLog {
    private static let lock = NSLock()
    private static var configured = false

    static func bootstrap(with locations: LibraryPaths) {
        lock.lock()
        defer { lock.unlock() }

        guard !configured else {
            AppLog.info(self, "bootstrap skipped already configured")
            return
        }
        try? locations.ensureDirectoriesExist()
        try? Dog.shared.initialization(writableDir: locations.logsDirectory)
        configured = true
        AppLog.info(self, "bootstrap completed logsDir=\(locations.logsDirectory.path)")
    }

    static func verbose(_ kind: Any, _ message: String) {
        Dog.shared.join(kind, message, level: .verbose)
    }

    static func info(_ kind: Any, _ message: String) {
        Dog.shared.join(kind, message, level: .info)
    }

    static func warning(_ kind: Any, _ message: String) {
        Dog.shared.join(kind, message, level: .warning)
    }

    static func error(_ kind: Any, _ message: String) {
        Dog.shared.join(kind, message, level: .error)
    }

    static func currentLogContent() -> String {
        Dog.shared.obtainCurrentLogContent()
    }

    static func allLogFiles() -> [URL] {
        Dog.shared.obtainAllLogFilePath().sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func clearLogs() throws {
        AppLog.info(self, "clearLogs entry")
        let logFiles = allLogFiles()
        let current = Dog.shared.currentLogFileLocation
        AppLog.verbose(self, "clearLogs totalFiles=\(logFiles.count) current=\(current?.path ?? "nil")")

        for file in logFiles {
            if file == current {
                let handle = try FileHandle(forWritingTo: file)
                try handle.truncate(atOffset: 0)
                try handle.close()
                AppLog.verbose(self, "clearLogs truncated current file")
            } else if FileManager.default.fileExists(atPath: file.path) {
                try FileManager.default.removeItem(at: file)
                AppLog.verbose(self, "clearLogs removed file=\(file.lastPathComponent)")
            }
        }
        AppLog.info(self, "clearLogs exit")
    }
}
