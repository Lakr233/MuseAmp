//
//  PlaylistRow.swift
//  AmMusicDatabaseKit
//
//  Created by @Lakr233 on 2026/04/11.
//

import Foundation
@preconcurrency import WCDBSwift

struct PlaylistRow: Codable, TableCodable {
    static let tableName = "playlists"

    var playlistID: String
    var name: String
    var coverImageData: Data?
    var createdAt: Date
    var updatedAt: Date

    init(from model: Playlist) {
        playlistID = model.id.uuidString
        name = model.name
        coverImageData = model.coverImageData
        createdAt = model.createdAt
        updatedAt = model.updatedAt
    }

    func toModel(entries: [PlaylistEntry]) -> Playlist {
        Playlist(
            id: UUID(uuidString: playlistID) ?? UUID(),
            name: name,
            coverImageData: coverImageData,
            entries: entries,
            createdAt: createdAt,
            updatedAt: updatedAt,
        )
    }

    enum CodingKeys: String, CodingTableKey {
        typealias Root = PlaylistRow

        static let objectRelationalMapping = TableBinding(CodingKeys.self) {
            BindColumnConstraint(playlistID, isPrimary: true, isNotNull: true, isUnique: true)
            BindColumnConstraint(name, isNotNull: true, defaultTo: "")
            BindColumnConstraint(createdAt, isNotNull: true, defaultTo: 0)
            BindColumnConstraint(updatedAt, isNotNull: true, defaultTo: 0)

            BindIndex(updatedAt, namedWith: "_playlist_updated_index")
        }

        case playlistID = "playlist_id"
        case name
        case coverImageData = "cover_image_data"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
