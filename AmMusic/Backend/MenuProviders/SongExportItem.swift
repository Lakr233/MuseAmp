//
//  SongExportItem.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import AmMusicDatabaseKit
import Foundation

nonisolated struct SongExportItem {
    let sourceURL: URL
    let preferredFileBaseName: String
    let trackID: String
    let albumID: String?
    let artworkURL: URL?
    let title: String
    let artistName: String
    let albumName: String?

    init(
        sourceURL: URL,
        artistName: String,
        title: String,
        trackID: String,
        albumID: String? = nil,
        albumName: String? = nil,
        artworkURL: URL? = nil,
        fallbackBaseName: String? = nil,
    ) {
        self.sourceURL = sourceURL
        self.trackID = trackID
        self.albumID = albumID
        self.artworkURL = artworkURL
        self.title = title
        self.artistName = artistName
        self.albumName = albumName
        let fallbackBaseName = fallbackBaseName ?? sourceURL.deletingPathExtension().lastPathComponent
        preferredFileBaseName = Self.preferredFileBaseName(
            artistName: artistName,
            title: title,
            fallbackBaseName: fallbackBaseName,
        )
    }
}

private nonisolated extension SongExportItem {
    static func preferredFileBaseName(
        artistName: String,
        title: String,
        fallbackBaseName: String,
    ) -> String {
        let artist = sanitizeDisplayFileName(artistName)
        let title = sanitizeDisplayFileName(title)

        if !artist.isEmpty, !title.isEmpty {
            return "\(artist) - \(title)"
        }
        if !title.isEmpty {
            return title
        }
        if !artist.isEmpty {
            return artist
        }

        return sanitizeDisplayFileName(fallbackBaseName, fallback: "Unknown")
    }
}
