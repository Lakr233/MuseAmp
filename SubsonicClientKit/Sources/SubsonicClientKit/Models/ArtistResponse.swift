//
//  ArtistResponse.swift
//  SubsonicClientKit
//
//  Created by @libr on 2026/04/16.
//

import Foundation

public struct ArtistResponse: Decodable, Sendable {
    public let artist: CatalogArtist
    public let albums: [CatalogAlbum]
    public let albumCount: Int?

    public init(artist: CatalogArtist, albums: [CatalogAlbum], albumCount: Int? = nil) {
        self.artist = artist
        self.albums = albums
        self.albumCount = albumCount
    }
}
