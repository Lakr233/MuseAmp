import Foundation

public enum TrackSourceKind: String, Sendable, Codable, Hashable {
    case downloaded
    case imported
    case restored
    case unknown
}
