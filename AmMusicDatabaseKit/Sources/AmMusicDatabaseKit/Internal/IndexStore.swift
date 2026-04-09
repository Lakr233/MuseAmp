import Foundation
@preconcurrency import WCDBSwift

struct IndexStore {
    private let database: WCDBSwift.Database
    let databaseURL: URL
    private let logger: DatabaseLogger

    init(databaseURL: URL, logger: DatabaseLogger) throws {
        self.databaseURL = databaseURL
        database = WCDBSwift.Database(at: databaseURL.path)
        self.logger = logger
        try createTablesIfNeeded()
    }

    func createTablesIfNeeded() throws {
        try database.create(table: TrackRow.tableName, of: TrackRow.self)
        try database.create(table: IndexMetaRow.tableName, of: IndexMetaRow.self)
    }

    func schemaVersion() throws -> Int? {
        try metaInt(for: "schema_version")
    }

    func formatVersion() throws -> Int? {
        try metaInt(for: "format_version")
    }

    func setSchemaVersions(schema: Int, format: Int) throws {
        try setMetaValue(String(schema), for: "schema_version")
        try setMetaValue(String(format), for: "format_version")
    }

    func setLastRebuild(timestamp: Date, succeeded: Bool) throws {
        try setMetaValue(String(timestamp.timeIntervalSince1970), for: "last_rebuild_timestamp")
        try setMetaValue(succeeded ? "1" : "0", for: "last_rebuild_succeeded")
    }

    func lastRebuildTimestamp() throws -> Date? {
        guard let value = try metaString(for: "last_rebuild_timestamp"), let interval = Double(value) else {
            return nil
        }
        return Date(timeIntervalSince1970: interval)
    }

    func lastRebuildSucceeded() throws -> Bool {
        try metaString(for: "last_rebuild_succeeded") == "1"
    }

    func allTracks() throws -> [AudioTrackRecord] {
        let rows: [TrackRow] = try database.getObjects(
            fromTable: TrackRow.tableName,
            orderBy: [TrackRow.Properties.artistName.order(.ascending), TrackRow.Properties.title.order(.ascending)]
        )
        return rows.map { $0.toModel() }
    }

    func track(byID trackID: String) throws -> AudioTrackRecord? {
        let row: TrackRow? = try database.getObject(
            fromTable: TrackRow.tableName,
            where: TrackRow.Properties.trackID == trackID
        )
        return row?.toModel()
    }

    func tracks(inAlbumID albumID: String) throws -> [AudioTrackRecord] {
        let rows: [TrackRow] = try database.getObjects(
            fromTable: TrackRow.tableName,
            where: TrackRow.Properties.albumID == albumID,
            orderBy: [
                TrackRow.Properties.discNumber.order(.ascending),
                TrackRow.Properties.trackNumber.order(.ascending),
                TrackRow.Properties.title.order(.ascending),
            ]
        )
        return rows.map { $0.toModel() }
    }

    func recentTracks(limit: Int) throws -> [AudioTrackRecord] {
        let rows: [TrackRow] = try database.getObjects(
            fromTable: TrackRow.tableName,
            orderBy: [TrackRow.Properties.updatedAt.order(.descending)],
            limit: limit
        )
        return rows.map { $0.toModel() }
    }

    func searchTracks(query: String, limit: Int) throws -> [AudioTrackRecord] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return []
        }

        let pattern = "%\(trimmed)%"
        let rows: [TrackRow] = try database.getObjects(
            fromTable: TrackRow.tableName,
            where: TrackRow.Properties.title.like(pattern)
                || TrackRow.Properties.artistName.like(pattern)
                || TrackRow.Properties.albumTitle.like(pattern),
            orderBy: [TrackRow.Properties.title.order(.ascending)],
            limit: limit
        )
        return rows.map { $0.toModel() }
    }

    func listAlbums() throws -> [AlbumGroup] {
        let grouped = try Dictionary(grouping: allTracks(), by: \.albumID)
        return grouped.values.compactMap { tracks in
            guard let first = tracks.first else {
                return nil
            }
            return AlbumGroup(
                albumID: first.albumID,
                albumTitle: first.albumTitle,
                artistName: first.albumArtistName ?? first.artistName,
                albumArtistName: first.albumArtistName,
                trackCount: tracks.count,
                artworkTrackID: tracks.first(where: \.hasEmbeddedArtwork)?.trackID,
                totalDurationSeconds: tracks.reduce(0) { $0 + $1.durationSeconds }
            )
        }
        .sorted {
            if $0.artistName == $1.artistName {
                return $0.albumTitle < $1.albumTitle
            }
            return $0.artistName < $1.artistName
        }
    }

    func librarySummary() throws -> LibrarySummary {
        let tracks = try allTracks()
        return LibrarySummary(
            trackCount: tracks.count,
            albumCount: Set(tracks.map(\.albumID)).count,
            totalSizeBytes: tracks.reduce(0) { $0 + $1.fileSizeBytes },
            totalDurationSeconds: tracks.reduce(0) { $0 + $1.durationSeconds }
        )
    }

    func trackSnapshotByRelativePath() throws -> [String: AudioTrackRecord] {
        try Dictionary(uniqueKeysWithValues: allTracks().map { ($0.relativePath, $0) })
    }

    func trackIDs() throws -> Set<String> {
        try Set(allTracks().map(\.trackID))
    }

    func allTrackRelativePaths() throws -> [String: String] {
        try Dictionary(uniqueKeysWithValues: allTracks().map { ($0.trackID, $0.relativePath) })
    }

    func upsertTracks(_ records: [AudioTrackRecord]) throws {
        guard !records.isEmpty else {
            return
        }

        try database.run(transaction: { _ in
            for record in records {
                try database.insertOrReplace(TrackRow(from: record), intoTable: TrackRow.tableName)
            }
        })
        DBLog.info(logger, "IndexStore", "upsertTracks count=\(records.count)")
    }

    func deleteTracks(relativePaths: [String]) throws {
        guard !relativePaths.isEmpty else {
            return
        }

        try database.run(transaction: { _ in
            for relativePath in relativePaths {
                try database.delete(
                    fromTable: TrackRow.tableName,
                    where: TrackRow.Properties.relativePath == relativePath
                )
            }
        })
        DBLog.info(logger, "IndexStore", "deleteTracks count=\(relativePaths.count)")
    }

    func deleteTrack(trackID: String) throws {
        try database.delete(
            fromTable: TrackRow.tableName,
            where: TrackRow.Properties.trackID == trackID
        )
    }

    func deleteAlbum(albumID: String) throws {
        try database.delete(
            fromTable: TrackRow.tableName,
            where: TrackRow.Properties.albumID == albumID
        )
    }

    func clearTracks() throws {
        try database.delete(fromTable: TrackRow.tableName)
    }

    private func metaString(for key: String) throws -> String? {
        let row: IndexMetaRow? = try database.getObject(
            fromTable: IndexMetaRow.tableName,
            where: IndexMetaRow.Properties.key == key
        )
        return row?.value
    }

    private func metaInt(for key: String) throws -> Int? {
        guard let value = try metaString(for: key) else {
            return nil
        }
        return Int(value)
    }

    private func setMetaValue(_ value: String, for key: String) throws {
        try database.insertOrReplace(
            IndexMetaRow(key: key, value: value),
            intoTable: IndexMetaRow.tableName
        )
    }
}
