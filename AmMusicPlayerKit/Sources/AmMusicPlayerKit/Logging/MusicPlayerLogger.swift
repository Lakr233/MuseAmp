public enum MusicPlayerLogLevel: String {
    case verbose
    case info
    case warning
    case error
}

public protocol MusicPlayerLogger: Sendable {
    func log(level: MusicPlayerLogLevel, component: String, message: String)
}

public struct NoopMusicPlayerLogger: MusicPlayerLogger {
    public init() {}

    public func log(level _: MusicPlayerLogLevel, component _: String, message _: String) {}
}
