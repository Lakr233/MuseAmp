//
//  PlayerItem.swift
//  AmMusicPlayerKit
//
//  Created by @Lakr233 on 2026/04/11.
//

import Foundation

public struct PlayerItem: Sendable, Hashable, Identifiable {
    public let id: String
    public let url: URL
    public let title: String
    public let artist: String
    public let album: String
    public let artworkURL: URL?
    public let durationInSeconds: TimeInterval?

    public init(
        id: String,
        url: URL,
        title: String,
        artist: String,
        album: String,
        artworkURL: URL? = nil,
        durationInSeconds: TimeInterval? = nil,
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.artist = artist
        self.album = album
        self.artworkURL = artworkURL
        self.durationInSeconds = durationInSeconds
    }
}
