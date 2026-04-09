import Foundation

public struct Playlist: Sendable, Codable, Hashable, Identifiable {
    public let id: UUID
    public var name: String
    public var coverImageData: Data?
    public var entries: [PlaylistEntry]
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        coverImageData: Data? = nil,
        entries: [PlaylistEntry] = [],
        createdAt: Date = .init(),
        updatedAt: Date = .init()
    ) {
        self.id = id
        self.name = name
        self.coverImageData = coverImageData
        self.entries = entries
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
