//
//  CatalogAlbumRelationships.swift
//  AmMusicKit
//
//  Created by @Lakr233 on 2026/04/11.
//

import Foundation

public struct CatalogAlbumRelationships: Decodable, Sendable {
    public let artists: ResourceList<CatalogArtist>?
    public let tracks: ResourceList<CatalogSong>?

    public init(
        artists: ResourceList<CatalogArtist>? = nil,
        tracks: ResourceList<CatalogSong>? = nil,
    ) {
        self.artists = artists
        self.tracks = tracks
    }
}
