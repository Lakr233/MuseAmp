import Foundation

public enum DatabaseFormat {
    public static let indexSchemaVersion = 1
    public static let indexFormatVersion = 1
    public static let stateSchemaVersion = 1
}

public enum DatabaseResetReason: Sendable, Hashable {
    case firstLaunch
    case indexVersionMismatch(oldSchema: Int?, oldFormat: Int?)
    case stateVersionMismatch(oldSchema: Int?)
    case corruption(dbName: String)
    case manualReset
}
