import Foundation
@preconcurrency import WCDBSwift

struct TrackRow: Codable, TableCodable {
    static let tableName = "tracks"

    var trackID: String
    var albumID: String
    var fileExtension: String
    var relativePath: String
    var fileSizeBytes: Int64
    var fileModifiedAt: Date
    var durationSeconds: Double
    var title: String
    var artistName: String
    var albumTitle: String
    var albumArtistName: String?
    var trackNumber: Int?
    var discNumber: Int?
    var genreName: String?
    var composerName: String?
    var releaseDate: String?
    var hasEmbeddedLyrics: Bool
    var hasEmbeddedArtwork: Bool
    var sourceKind: String
    var createdAt: Date
    var updatedAt: Date

    init(from model: AudioTrackRecord) {
        trackID = model.trackID
        albumID = model.albumID
        fileExtension = model.fileExtension
        relativePath = model.relativePath
        fileSizeBytes = model.fileSizeBytes
        fileModifiedAt = model.fileModifiedAt
        durationSeconds = model.durationSeconds
        title = model.title
        artistName = model.artistName
        albumTitle = model.albumTitle
        albumArtistName = model.albumArtistName
        trackNumber = model.trackNumber
        discNumber = model.discNumber
        genreName = model.genreName
        composerName = model.composerName
        releaseDate = model.releaseDate
        hasEmbeddedLyrics = model.hasEmbeddedLyrics
        hasEmbeddedArtwork = model.hasEmbeddedArtwork
        sourceKind = model.sourceKind.rawValue
        createdAt = model.createdAt
        updatedAt = model.updatedAt
    }

    func toModel() -> AudioTrackRecord {
        AudioTrackRecord(
            trackID: trackID,
            albumID: albumID,
            fileExtension: fileExtension,
            relativePath: relativePath,
            fileSizeBytes: fileSizeBytes,
            fileModifiedAt: fileModifiedAt,
            durationSeconds: durationSeconds,
            title: title,
            artistName: artistName,
            albumTitle: albumTitle,
            albumArtistName: albumArtistName,
            trackNumber: trackNumber,
            discNumber: discNumber,
            genreName: genreName,
            composerName: composerName,
            releaseDate: releaseDate,
            hasEmbeddedLyrics: hasEmbeddedLyrics,
            hasEmbeddedArtwork: hasEmbeddedArtwork,
            sourceKind: TrackSourceKind(rawValue: sourceKind) ?? .unknown,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    enum CodingKeys: String, CodingTableKey {
        typealias Root = TrackRow

        static let objectRelationalMapping = TableBinding(CodingKeys.self) {
            BindColumnConstraint(trackID, isPrimary: true, isNotNull: true, isUnique: true)
            BindColumnConstraint(albumID, isNotNull: true, defaultTo: "")
            BindColumnConstraint(fileExtension, isNotNull: true, defaultTo: "")
            BindColumnConstraint(relativePath, isNotNull: true, isUnique: true, defaultTo: "")
            BindColumnConstraint(fileSizeBytes, isNotNull: true, defaultTo: 0)
            BindColumnConstraint(fileModifiedAt, isNotNull: true, defaultTo: 0)
            BindColumnConstraint(durationSeconds, isNotNull: true, defaultTo: 0)
            BindColumnConstraint(title, isNotNull: true, defaultTo: "")
            BindColumnConstraint(artistName, isNotNull: true, defaultTo: "")
            BindColumnConstraint(albumTitle, isNotNull: true, defaultTo: "")
            BindColumnConstraint(hasEmbeddedLyrics, isNotNull: true, defaultTo: false)
            BindColumnConstraint(hasEmbeddedArtwork, isNotNull: true, defaultTo: false)
            BindColumnConstraint(sourceKind, isNotNull: true, defaultTo: TrackSourceKind.unknown.rawValue)
            BindColumnConstraint(createdAt, isNotNull: true, defaultTo: 0)
            BindColumnConstraint(updatedAt, isNotNull: true, defaultTo: 0)

            BindIndex(relativePath, namedWith: "_relative_path_index")
            BindIndex(albumID, namedWith: "_album_id_index")
            BindIndex(artistName, namedWith: "_artist_name_index")
            BindIndex(albumTitle, namedWith: "_album_title_index")
            BindIndex(updatedAt, namedWith: "_updated_at_index")
        }

        case trackID = "track_id"
        case albumID = "album_id"
        case fileExtension = "file_extension"
        case relativePath = "relative_path"
        case fileSizeBytes = "file_size_bytes"
        case fileModifiedAt = "file_modified_at"
        case durationSeconds = "duration_seconds"
        case title
        case artistName = "artist_name"
        case albumTitle = "album_title"
        case albumArtistName = "album_artist_name"
        case trackNumber = "track_number"
        case discNumber = "disc_number"
        case genreName = "genre_name"
        case composerName = "composer_name"
        case releaseDate = "release_date"
        case hasEmbeddedLyrics = "has_embedded_lyrics"
        case hasEmbeddedArtwork = "has_embedded_artwork"
        case sourceKind = "source_kind"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
