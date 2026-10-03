//
//  CatalogSongAttributes.swift
//  SubsonicClientKit
//
//  Created by @Lakr233 on 2026/04/11.
//

import Foundation

public struct CatalogSongAttributes: Decodable, Hashable, Sendable {
    public let name: String
    public let artistName: String
    public let albumName: String?
    public let durationInMillis: Int?
    public let trackNumber: Int?
    public let discNumber: Int?
    public let releaseDate: String?
    public let composerName: String?
    public let audioTraits: [String]?
    public let contentRating: String?
    public let hasLyrics: Bool?
    public let artwork: Artwork?
    public let playParams: CatalogPlayParams?

    public init(
        name: String,
        artistName: String,
        albumName: String? = nil,
        durationInMillis: Int? = nil,
        trackNumber: Int? = nil,
        discNumber: Int? = nil,
        releaseDate: String? = nil,
        composerName: String? = nil,
        audioTraits: [String]? = nil,
        contentRating: String? = nil,
        hasLyrics: Bool? = nil,
        artwork: Artwork? = nil,
        playParams: CatalogPlayParams? = nil,
    ) {
        self.name = name
        self.artistName = artistName
        self.albumName = albumName
        self.durationInMillis = durationInMillis
        self.trackNumber = trackNumber
        self.discNumber = discNumber
        self.releaseDate = releaseDate
        self.composerName = composerName
        self.audioTraits = audioTraits
        self.contentRating = contentRating
        self.hasLyrics = hasLyrics
        self.artwork = artwork
        self.playParams = playParams
    }
}
