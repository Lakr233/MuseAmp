//
//  PlaylistSong+AppModels.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import AmMusicDatabaseKit
import Foundation

extension PlaylistEntry {
    nonisolated func downloadRequest(albumID: String, apiBaseURL: URL?) -> SongDownloadRequest {
        SongDownloadRequest(
            trackID: trackID,
            albumID: albumID,
            title: title,
            artistName: artistName,
            albumName: albumTitle,
            artworkURL: APIClient.resolveMediaURL(artworkURL, width: 600, height: 600, baseURL: apiBaseURL),
        )
    }
}
