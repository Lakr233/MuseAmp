//
//  SongExportItem.swift
//  MuseAmp
//
//  Created by @Lakr233 on 2026/04/11.
//

import Foundation
import MuseAmpDatabaseKit

nonisolated struct SongExportItem {
    let sourceURL: URL
    let preferredFileBaseName: String
    let trackID: String
    let albumID: String?
    let artworkURL: URL?
    let title: String
    let artistName: String
    let albumName: String?
    let albumArtistName: String?
    let trackNumber: Int?
    let discNumber: Int?
    let genreName: String?
    let composerName: String?
    let releaseDate: String?

    init(
        sourceURL: URL,
        artistName: String,
        title: String,
        trackID: String,
        albumID: String? = nil,
        albumName: String? = nil,
        artworkURL: URL? = nil,
        albumArtistName: String? = nil,
        trackNumber: Int? = nil,
        discNumber: Int? = nil,
        genreName: String? = nil,
        composerName: String? = nil,
        releaseDate: String? = nil,
        fallbackBaseName: String? = nil,
    ) {
        self.sourceURL = sourceURL
        self.trackID = trackID
        self.albumID = albumID
        self.artworkURL = artworkURL
        self.title = title
        self.artistName = artistName
        self.albumName = albumName
        self.albumArtistName = albumArtistName
        self.trackNumber = trackNumber
        self.discNumber = discNumber
        self.genreName = genreName
        self.composerName = composerName
        self.releaseDate = releaseDate
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
