import Foundation

public enum DatabaseLogLevel: String, Sendable {
    case verbose
    case info
    case warning
    case error
    case critical
}

public typealias LogSink = @Sendable (_ level: DatabaseLogLevel, _ scope: String, _ message: String) -> Void

struct DatabaseLogger {
    private let sink: LogSink?

    init(sink: LogSink?) {
        self.sink = sink
    }

    func log(_ level: DatabaseLogLevel, _ scope: String, _ message: String) {
        sink?(level, scope, message)
    }

    func verbose(_ scope: String, _ message: String) {
        log(.verbose, scope, message)
    }

    func info(_ scope: String, _ message: String) {
        log(.info, scope, message)
    }

    func warning(_ scope: String, _ message: String) {
        log(.warning, scope, message)
    }

    func error(_ scope: String, _ message: String) {
        log(.error, scope, message)
    }

    func critical(_ scope: String, _ message: String) {
        log(.critical, scope, message)
    }
}

enum DBLog {
    static func verbose(_ logger: DatabaseLogger, _ scope: String, _ message: String) {
        logger.verbose(scope, message)
    }

    static func info(_ logger: DatabaseLogger, _ scope: String, _ message: String) {
        logger.info(scope, message)
    }

    static func warning(_ logger: DatabaseLogger, _ scope: String, _ message: String) {
        logger.warning(scope, message)
    }

    static func error(_ logger: DatabaseLogger, _ scope: String, _ message: String) {
        logger.error(scope, message)
    }

    static func critical(_ logger: DatabaseLogger, _ scope: String, _ message: String) {
        logger.critical(scope, message)
    }
}
