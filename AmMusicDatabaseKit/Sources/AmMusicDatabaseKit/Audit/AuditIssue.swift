import Foundation

public struct AuditIssue: Sendable, Codable, Hashable, Identifiable {
    public enum Severity: String, Sendable, Codable, Hashable {
        case info
        case warning
        case error
        case critical
    }

    public let id: String
    public let severity: Severity
    public let code: String
    public let message: String

    public init(
        id: String = UUID().uuidString,
        severity: Severity,
        code: String,
        message: String
    ) {
        self.id = id
        self.severity = severity
        self.code = code
        self.message = message
    }
}
