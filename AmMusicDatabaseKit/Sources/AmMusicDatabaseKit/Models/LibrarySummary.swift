import Foundation

public struct LibrarySummary: Sendable, Codable, Hashable {
    public let trackCount: Int
    public let albumCount: Int
    public let totalSizeBytes: Int64
    public let totalDurationSeconds: Double

    public init(
        trackCount: Int,
        albumCount: Int,
        totalSizeBytes: Int64,
        totalDurationSeconds: Double
    ) {
        self.trackCount = trackCount
        self.albumCount = albumCount
        self.totalSizeBytes = totalSizeBytes
        self.totalDurationSeconds = totalDurationSeconds
    }
}
