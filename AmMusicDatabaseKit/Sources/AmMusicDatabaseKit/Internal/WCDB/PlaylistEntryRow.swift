//
//  PlaylistEntryRow.swift
//  AmMusicDatabaseKit
//
//  Created by @Lakr233 on 2026/04/11.
//

import Foundation
@preconcurrency import WCDBSwift

struct PlaylistEntryRow: Codable, TableCodable {
    static let tableName = "playlist_entries"

    var entryID: String
    var playlistID: String
    var trackID: String
    var title: String
    var artistName: String
    var albumID: String?
    var albumTitle: String?
    var artworkURL: String?
    var durationMillis: Int?
    var trackNumber: Int?
    var lyrics: String?
    var position: Int
    var createdAt: Date

    init(
        entry: PlaylistEntry,
        playlistID: UUID,
        position: Int,
        createdAt: Date = .init(),
    ) {
        entryID = entry.entryID
        self.playlistID = playlistID.uuidString
        trackID = entry.trackID
        title = entry.title
        artistName = entry.artistName
        albumID = entry.albumID
        albumTitle = entry.albumTitle
        artworkURL = entry.artworkURL
        durationMillis = entry.durationMillis
        trackNumber = entry.trackNumber
        lyrics = entry.lyrics
        self.position = position
        self.createdAt = createdAt
    }

    func toModel() -> PlaylistEntry {
        PlaylistEntry(
            entryID: entryID,
            trackID: trackID,
            title: title,
            artistName: artistName,
            albumID: albumID,
            albumTitle: albumTitle,
            artworkURL: artworkURL,
            durationMillis: durationMillis,
            trackNumber: trackNumber,
            lyrics: lyrics,
        )
    }

    enum CodingKeys: String, CodingTableKey {
        typealias Root = PlaylistEntryRow

        static let objectRelationalMapping = TableBinding(CodingKeys.self) {
            BindColumnConstraint(entryID, isPrimary: true, isNotNull: true, isUnique: true)
            BindColumnConstraint(playlistID, isNotNull: true, defaultTo: "")
            BindColumnConstraint(trackID, isNotNull: true, defaultTo: "")
            BindColumnConstraint(title, isNotNull: true, defaultTo: "")
            BindColumnConstraint(artistName, isNotNull: true, defaultTo: "")
            BindColumnConstraint(position, isNotNull: true, defaultTo: 0)
            BindColumnConstraint(createdAt, isNotNull: true, defaultTo: 0)

            BindIndex(playlistID, namedWith: "_playlist_entry_playlist_index")
            BindIndex(trackID, namedWith: "_playlist_entry_track_index")
        }

        case entryID = "entry_id"
        case playlistID = "playlist_id"
        case trackID = "track_id"
        case title
        case artistName = "artist_name"
        case albumID = "album_id"
        case albumTitle = "album_title"
        case artworkURL = "artwork_url"
        case durationMillis = "duration_millis"
        case trackNumber = "track_number"
        case lyrics
        case position
        case createdAt = "created_at"
    }
}
