import Foundation

public enum DownloadJobStatus: String, Sendable, Codable, CaseIterable, Hashable {
    case queued
    case waitingForNetwork
    case resolving
    case downloading
    case finalizing
    case failed

    public var isActive: Bool {
        switch self {
        case .queued, .waitingForNetwork, .resolving, .downloading, .finalizing:
            true
        case .failed:
            false
        }
    }
}
