import Foundation

nonisolated enum PlaybackSource: Codable, Hashable {
    case library
    case album(id: String)
    case playlist(UUID)
    case search(query: String?)
    case downloads
    case adHoc(name: String)

    private enum CodingKeys: String, CodingKey {
        case type
        case id
        case playlistID
        case query
        case name
    }

    private enum Kind: String, Codable {
        case library
        case album
        case playlist
        case search
        case downloads
        case adHoc
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .library:
            self = .library
        case .album:
            self = try .album(id: container.decode(String.self, forKey: .id))
        case .playlist:
            self = try .playlist(container.decode(UUID.self, forKey: .playlistID))
        case .search:
            self = try .search(query: container.decodeIfPresent(String.self, forKey: .query))
        case .downloads:
            self = .downloads
        case .adHoc:
            self = try .adHoc(name: container.decode(String.self, forKey: .name))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .library:
            try container.encode(Kind.library, forKey: .type)
        case let .album(id):
            try container.encode(Kind.album, forKey: .type)
            try container.encode(id, forKey: .id)
        case let .playlist(id):
            try container.encode(Kind.playlist, forKey: .type)
            try container.encode(id, forKey: .playlistID)
        case let .search(query):
            try container.encode(Kind.search, forKey: .type)
            try container.encodeIfPresent(query, forKey: .query)
        case .downloads:
            try container.encode(Kind.downloads, forKey: .type)
        case let .adHoc(name):
            try container.encode(Kind.adHoc, forKey: .type)
            try container.encode(name, forKey: .name)
        }
    }
}
