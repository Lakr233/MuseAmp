//
//  SongDownloadRequest.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import Foundation

nonisolated struct SongDownloadRequest {
    let trackID: String
    let albumID: String
    let title: String
    let artistName: String
    let albumName: String?
    let artworkURL: URL?
}
