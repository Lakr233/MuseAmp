//
//  AppLog.swift
//  MuseAmp
//
//  Created by @Lakr233 on 2026/04/11.
//

import Dog
import Foundation
import MuseAmpDatabaseKit

nonisolated enum AppLog {
    private static let lock = NSLock()
    /// Guarded by `lock`. Not main-actor-isolated so callers on any thread
    /// (bootstrap runs from background setup code) can hit AppLog without
    /// hopping actors.
    private nonisolated(unsafe) static var configured = false

    static func bootstrap(with locations: LibraryPaths) {
        lock.lock()
        if configured {
            lock.unlock()
            AppLog.info(self, "bootstrap skipped already configured")
            return
        }
        try? locations.ensureDirectoriesExist()
        try? Dog.shared.initialization(writableDir: locations.logsDirectory)
        configured = true
        lock.unlock()
        AppLog.info(self, "bootstrap completed logsDir=\(locations.logsDirectory.path)")
    }

    static func verbose(_ kind: Any, _ message: String) {
        Dog.shared.join(categoryName(for: kind), message, level: .verbose)
    }

    static func info(_ kind: Any, _ message: String) {
        Dog.shared.join(categoryName(for: kind), message, level: .info)
    }

    static func warning(_ kind: Any, _ message: String) {
        Dog.shared.join(categoryName(for: kind), message, level: .warning)
    }

    static func error(_ kind: Any, _ message: String) {
        Dog.shared.join(categoryName(for: kind), message, level: .error)
    }

    /// Normalizes an arbitrary log "kind" into a stable, short category name.
    ///
    /// - `String` passes through untouched, letting callers supply explicit tags.
    /// - A metatype (`Foo.self`) becomes its short description (`"Foo"`).
    /// - Any other value falls back to `type(of:)` so class instances (including
    ///   `NSObject` subclasses) never leak pointer-address strings into the log
    ///   header, which used to produce one filter entry per instance.
    /// - Finally the module prefix is stripped so `"MuseAmp.PlaybackController"`
    ///   collapses to `"PlaybackController"`.
    static func categoryName(for kind: Any) -> String {
        if let string = kind as? String {
            return sanitizeCategoryName(string)
        }
        let typeName = if let type = kind as? Any.Type {
            String(describing: type)
        } else {
            String(describing: type(of: kind))
        }
        let name = typeName.split(separator: ".").last.map(String.init) ?? typeName
        return sanitizeCategoryName(name)
    }

    /// Strips characters that conflict with the Dog log format delimiters
    /// (`[`, `]`, `|`, newlines) so category headers parse cleanly.
    private static func sanitizeCategoryName(_ name: String) -> String {
        guard !name.isEmpty else { return "Unknown" }
        var sanitized = name
        for ch: Character in ["[", "]", "|", "\n"] {
            sanitized = sanitized.filter { $0 != ch }
        }
        return sanitized.isEmpty ? "Unknown" : sanitized
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

extension AppLog {
    /// Layout-specific log channel. Tags messages with a `ClassName+Layout`
    /// category so view-layout state transitions are one menu item away in the
    /// log viewer's category filter.
    enum Layout {
        static func verbose(_ kind: Any, _ message: String) {
            log(kind, message, level: .verbose)
        }

        static func info(_ kind: Any, _ message: String) {
            log(kind, message, level: .info)
        }

        static func warning(_ kind: Any, _ message: String) {
            log(kind, message, level: .warning)
        }

        static func error(_ kind: Any, _ message: String) {
            log(kind, message, level: .error)
        }

        private static func log(_ kind: Any, _ message: String, level: Dog.DogLevel) {
            Dog.shared.join("\(AppLog.categoryName(for: kind))+Layout", message, level: level)
        }
    }
}
