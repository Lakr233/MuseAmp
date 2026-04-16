//
//  SubsonicArtist.swift
//  SubsonicClientKit
//
//  Created by @Lakr233 on 2026/04/14.
//

import Foundation

struct SubsonicArtistPayload: Decodable {
    let artist: SubsonicArtist?
}

struct SubsonicArtist: Decodable, Sendable {
    let id: String
    let name: String
    let coverArt: String?
    let artistImageUrl: String?
    let albumCount: Int?
    let albums: [SubsonicAlbum]

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case coverArt
        case artistImageUrl
        case albumCount
        case albums = "album"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeLossyString(forKey: .id)
        name = try container.decodeLossyString(forKey: .name)
        coverArt = try container.decodeLossyStringIfPresent(forKey: .coverArt)
        artistImageUrl = try container.decodeLossyStringIfPresent(forKey: .artistImageUrl)
        albumCount = try container.decodeLossyIntIfPresent(forKey: .albumCount)
        albums = try container.decodeIfPresent([SubsonicAlbum].self, forKey: .albums) ?? []
    }
}
