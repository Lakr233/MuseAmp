//
//  SearchResults.swift
//  AmMusicKit
//
//  Created by @Lakr233 on 2026/04/11.
//

import Foundation

public struct SearchResults: Decodable, Sendable {
    public let songs: ResourceList<CatalogSong>?
    public let albums: ResourceList<CatalogAlbum>?
    public let artists: ResourceList<CatalogArtist>?

    public init(
        songs: ResourceList<CatalogSong>? = nil,
        albums: ResourceList<CatalogAlbum>? = nil,
        artists: ResourceList<CatalogArtist>? = nil,
    ) {
        self.songs = songs
        self.albums = albums
        self.artists = artists
    }
}
