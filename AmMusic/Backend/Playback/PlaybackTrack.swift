//
//  PlaybackTrack.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import AmMusicDatabaseKit
import AmMusicKit
import Foundation

nonisolated struct PlaybackTrack: Identifiable, Hashable {
    let id: String
    let title: String
    let artistName: String
    let albumName: String?
    let albumID: String?
    let artworkURL: URL?
    let durationInSeconds: TimeInterval?
    let localFileURL: URL?

    init(
        id: String,
        title: String,
        artistName: String,
        albumName: String? = nil,
        albumID: String? = nil,
        artworkURL: URL? = nil,
        durationInSeconds: TimeInterval? = nil,
        localFileURL: URL? = nil,
    ) {
        self.id = id
        self.title = title
        self.artistName = artistName
        self.albumName = albumName
        self.albumID = albumID
        self.artworkURL = artworkURL
        self.durationInSeconds = durationInSeconds
        self.localFileURL = localFileURL
    }

    var playlistEntry: PlaylistEntry {
        PlaylistEntry(
            trackID: id,
            title: title,
            artistName: artistName,
            albumTitle: albumName,
            durationMillis: durationInSeconds.map { Int(($0 * 1000).rounded()) },
        )
    }
}

extension CatalogSong {
    func playbackTrack(apiClient: APIClient) -> PlaybackTrack {
        PlaybackTrack(
            id: id,
            title: attributes.name,
            artistName: attributes.artistName,
            albumName: attributes.albumName,
            albumID: relationships?.albums?.data.first?.id,
            artworkURL: apiClient.mediaURL(from: attributes.artwork?.url, width: 600, height: 600),
            durationInSeconds: attributes.durationInMillis.map { TimeInterval($0) / 1000 },
        )
    }
}

extension PlaylistEntry {
    func playbackTrack(apiClient: APIClient) -> PlaybackTrack {
        PlaybackTrack(
            id: trackID,
            title: title,
            artistName: artistName,
            albumName: albumTitle,
            albumID: albumID,
            artworkURL: apiClient.mediaURL(from: artworkURL, width: 600, height: 600),
            durationInSeconds: durationMillis.map { TimeInterval($0) / 1000 },
        )
    }
}
