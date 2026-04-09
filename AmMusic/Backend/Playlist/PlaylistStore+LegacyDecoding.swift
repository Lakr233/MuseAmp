import AmMusicDatabaseKit
import Foundation

struct LegacyPlaylist: Decodable {
    let playlist: Playlist

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case coverImageData
        case songs
        case createdAt
        case updatedAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let identifier =
            (try? container.decode(UUID.self, forKey: .id))
                ?? (try? container.decode(String.self, forKey: .id)).flatMap(UUID.init(uuidString:))
                ?? UUID()
        let name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Playlist"
        let coverImageData = try container.decodeIfPresent(Data.self, forKey: .coverImageData)
        let songs =
            try container.decodeIfPresent([LegacyPlaylistSong].self, forKey: .songs)?.map(\.playlistEntry)
                ?? []
        let createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .init()
        let updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt

        playlist = Playlist(
            id: identifier,
            name: name,
            coverImageData: coverImageData,
            entries: songs,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

struct LegacyPlaylistSong: Decodable {
    let playlistEntry: PlaylistEntry

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case artistName
        case artworkURL
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name =
            try container.decodeIfPresent(String.self, forKey: .name) ?? String(localized: "Unknown Song")
        let artistName =
            try container.decodeIfPresent(String.self, forKey: .artistName)
                ?? String(localized: "Unknown Artist")
        let identifier = try container.decodeIfPresent(String.self, forKey: .id) ?? name
        let artworkURL = try container.decodeIfPresent(String.self, forKey: .artworkURL)
        playlistEntry = PlaylistEntry(
            trackID: identifier,
            title: name,
            artistName: artistName,
            artworkURL: artworkURL
        )
    }
}
