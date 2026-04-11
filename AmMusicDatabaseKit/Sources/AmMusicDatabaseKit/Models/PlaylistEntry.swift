//
//  PlaylistEntry.swift
//  AmMusicDatabaseKit
//
//  Created by @Lakr233 on 2026/04/11.
//

import Foundation

public struct PlaylistEntry: Sendable, Codable, Hashable, Identifiable {
    public let entryID: String
    public var id: String {
        entryID
    }

    public let trackID: String
    public let title: String
    public let artistName: String
    public let albumID: String?
    public let albumTitle: String?
    public let artworkURL: String?
    public let durationMillis: Int?
    public let trackNumber: Int?
    public let lyrics: String?

    public init(
        entryID: String = UUID().uuidString,
        trackID: String,
        title: String,
        artistName: String,
        albumID: String? = nil,
        albumTitle: String? = nil,
        artworkURL: String? = nil,
        durationMillis: Int? = nil,
        trackNumber: Int? = nil,
        lyrics: String? = nil,
    ) {
        self.entryID = entryID
        self.trackID = trackID
        self.title = title
        self.artistName = artistName
        self.albumID = albumID
        self.albumTitle = albumTitle
        self.artworkURL = artworkURL
        self.durationMillis = durationMillis
        self.trackNumber = trackNumber
        self.lyrics = lyrics
    }
}
