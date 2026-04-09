import Foundation
@preconcurrency import WCDBSwift

struct StateStore {
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
        try database.create(table: StateMetaRow.tableName, of: StateMetaRow.self)
        try database.create(table: DownloadJobRow.tableName, of: DownloadJobRow.self)
        try database.create(table: PlaylistRow.tableName, of: PlaylistRow.self)
        try database.create(table: PlaylistEntryRow.tableName, of: PlaylistEntryRow.self)
    }

    func schemaVersion() throws -> Int? {
        try metaInt(for: "schema_version")
    }

    func setSchemaVersion(_ version: Int) throws {
        try setMetaValue(String(version), for: "schema_version")
    }

    func migrateIfNeeded(from oldVersion: Int?, to newVersion: Int) throws {
        guard oldVersion != newVersion else {
            return
        }
        try createTablesIfNeeded()
        try setSchemaVersion(newVersion)
    }

    func allDownloads() throws -> [DownloadJob] {
        let rows: [DownloadJobRow] = try database.getObjects(
            fromTable: DownloadJobRow.tableName,
            orderBy: [DownloadJobRow.Properties.updatedAt.order(.descending)]
        )
        return rows.map { $0.toModel() }
    }

    func activeDownloads() throws -> [DownloadJob] {
        let rows: [DownloadJobRow] = try database.getObjects(
            fromTable: DownloadJobRow.tableName,
            where: DownloadJobRow.Properties.status == DownloadJobStatus.queued.rawValue
                || DownloadJobRow.Properties.status == DownloadJobStatus.waitingForNetwork.rawValue
                || DownloadJobRow.Properties.status == DownloadJobStatus.resolving.rawValue
                || DownloadJobRow.Properties.status == DownloadJobStatus.downloading.rawValue
                || DownloadJobRow.Properties.status == DownloadJobStatus.finalizing.rawValue,
            orderBy: [DownloadJobRow.Properties.updatedAt.order(.descending)]
        )
        return rows.map { $0.toModel() }
    }

    func failedDownloads() throws -> [DownloadJob] {
        let rows: [DownloadJobRow] = try database.getObjects(
            fromTable: DownloadJobRow.tableName,
            where: DownloadJobRow.Properties.status == DownloadJobStatus.failed.rawValue,
            orderBy: [DownloadJobRow.Properties.updatedAt.order(.descending)]
        )
        return rows.map { $0.toModel() }
    }

    func download(trackID: String) throws -> DownloadJob? {
        let row: DownloadJobRow? = try database.getObject(
            fromTable: DownloadJobRow.tableName,
            where: DownloadJobRow.Properties.trackID == trackID,
            orderBy: [DownloadJobRow.Properties.updatedAt.order(.descending)]
        )
        return row?.toModel()
    }

    func upsertDownload(_ job: DownloadJob) throws {
        try database.insertOrReplace(DownloadJobRow(from: job), intoTable: DownloadJobRow.tableName)
    }

    func deleteDownload(trackID: String) throws {
        try database.delete(
            fromTable: DownloadJobRow.tableName,
            where: DownloadJobRow.Properties.trackID == trackID
        )
    }

    func deleteDownloads(trackIDs: [String]) throws {
        guard !trackIDs.isEmpty else {
            return
        }
        try database.run(transaction: { _ in
            for trackID in trackIDs {
                try database.delete(
                    fromTable: DownloadJobRow.tableName,
                    where: DownloadJobRow.Properties.trackID == trackID
                )
            }
        })
    }

    func fetchPlaylists() throws -> [Playlist] {
        let rows: [PlaylistRow] = try database.getObjects(
            fromTable: PlaylistRow.tableName,
            orderBy: [PlaylistRow.Properties.updatedAt.order(.descending)]
        )
        return try rows.map(makePlaylist(from:))
    }

    func fetchPlaylist(id: UUID) throws -> Playlist? {
        guard let row: PlaylistRow = try database.getObject(
            fromTable: PlaylistRow.tableName,
            where: PlaylistRow.Properties.playlistID == id.uuidString
        ) else {
            return nil
        }
        return try makePlaylist(from: row)
    }

    func createPlaylist(id: UUID = UUID(), name: String, coverImageData: Data? = nil) throws -> Playlist {
        let playlist = Playlist(id: id, name: name, coverImageData: coverImageData, entries: [])
        try database.insert(PlaylistRow(from: playlist), intoTable: PlaylistRow.tableName)
        return playlist
    }

    func renamePlaylist(id: UUID, name: String) throws {
        guard var row: PlaylistRow = try database.getObject(
            fromTable: PlaylistRow.tableName,
            where: PlaylistRow.Properties.playlistID == id.uuidString
        ) else {
            return
        }
        row.name = name
        row.updatedAt = .init()
        try database.insertOrReplace(row, intoTable: PlaylistRow.tableName)
    }

    func deletePlaylist(id: UUID) throws {
        try database.run(transaction: { _ in
            try database.delete(
                fromTable: PlaylistEntryRow.tableName,
                where: PlaylistEntryRow.Properties.playlistID == id.uuidString
            )
            try database.delete(
                fromTable: PlaylistRow.tableName,
                where: PlaylistRow.Properties.playlistID == id.uuidString
            )
        })
    }

    func updatePlaylistCover(id: UUID, imageData: Data?) throws {
        guard var row: PlaylistRow = try database.getObject(
            fromTable: PlaylistRow.tableName,
            where: PlaylistRow.Properties.playlistID == id.uuidString
        ) else {
            return
        }
        row.coverImageData = imageData
        row.updatedAt = .init()
        try database.insertOrReplace(row, intoTable: PlaylistRow.tableName)
    }

    func addPlaylistEntry(_ entry: PlaylistEntry, playlistID: UUID) throws {
        var entries = try playlistEntryRows(playlistID: playlistID)
        entries.append(PlaylistEntryRow(entry: entry, playlistID: playlistID, position: entries.count))
        try savePlaylistEntries(entries, playlistID: playlistID)
    }

    func removePlaylistEntry(index: Int, playlistID: UUID) throws {
        var entries = try playlistEntryRows(playlistID: playlistID)
        guard entries.indices.contains(index) else {
            return
        }
        entries.remove(at: index)
        try savePlaylistEntries(entries, playlistID: playlistID)
    }

    func movePlaylistEntry(playlistID: UUID, from: Int, to: Int) throws {
        var entries = try playlistEntryRows(playlistID: playlistID)
        guard entries.indices.contains(from), entries.indices.contains(to) || to == entries.count else {
            return
        }
        let row = entries.remove(at: from)
        entries.insert(row, at: max(0, min(to, entries.count)))
        try savePlaylistEntries(entries, playlistID: playlistID)
    }

    func updateEntryLyrics(_ lyrics: String, trackID: String, playlistID: UUID) throws {
        var entries = try playlistEntryRows(playlistID: playlistID)
        guard let index = entries.firstIndex(where: { $0.trackID == trackID }) else {
            return
        }
        entries[index].lyrics = lyrics
        try savePlaylistEntries(entries, playlistID: playlistID)
    }

    func clearPlaylistEntries(playlistID: UUID) throws {
        try savePlaylistEntries([], playlistID: playlistID)
    }

    func importLegacyPlaylists(_ playlists: [Playlist]) throws {
        guard !playlists.isEmpty else {
            return
        }
        try database.run(transaction: { _ in
            for playlist in playlists {
                try database.insertOrReplace(PlaylistRow(from: playlist), intoTable: PlaylistRow.tableName)
                try database.delete(
                    fromTable: PlaylistEntryRow.tableName,
                    where: PlaylistEntryRow.Properties.playlistID == playlist.id.uuidString
                )
                for (index, entry) in playlist.entries.enumerated() {
                    try database.insert(
                        PlaylistEntryRow(entry: entry, playlistID: playlist.id, position: index, createdAt: playlist.updatedAt),
                        intoTable: PlaylistEntryRow.tableName
                    )
                }
            }
        })
    }

    func duplicatePlaylist(id: UUID) throws -> Playlist? {
        guard var playlist = try fetchPlaylist(id: id) else {
            return nil
        }
        let duplicatedEntries = playlist.entries.map {
            PlaylistEntry(
                trackID: $0.trackID,
                title: $0.title,
                artistName: $0.artistName,
                albumID: $0.albumID,
                albumTitle: $0.albumTitle,
                artworkURL: $0.artworkURL,
                durationMillis: $0.durationMillis,
                trackNumber: $0.trackNumber,
                lyrics: $0.lyrics
            )
        }
        playlist = Playlist(
            id: UUID(),
            name: String(
                format: String(localized: "%@ Copy", bundle: .module),
                locale: .current,
                playlist.name
            ),
            coverImageData: playlist.coverImageData,
            entries: duplicatedEntries,
            createdAt: .init(),
            updatedAt: .init()
        )
        try importLegacyPlaylists([playlist])
        return playlist
    }

    func playlistCount() throws -> Int {
        try database.getValue(
            on: PlaylistRow.Properties.playlistID.count(),
            fromTable: PlaylistRow.tableName
        ).intValue
    }

    func playlistEntryCount() throws -> Int {
        try database.getValue(
            on: PlaylistEntryRow.Properties.entryID.count(),
            fromTable: PlaylistEntryRow.tableName
        ).intValue
    }

    func unresolvedPlaylistEntryCount(validTrackIDs: Set<String>) throws -> Int {
        let rows: [PlaylistEntryRow] = try database.getObjects(fromTable: PlaylistEntryRow.tableName)
        return rows.reduce(into: 0) { count, row in
            if !validTrackIDs.contains(row.trackID) {
                count += 1
            }
        }
    }

    private func playlistEntryRows(playlistID: UUID) throws -> [PlaylistEntryRow] {
        try database.getObjects(
            fromTable: PlaylistEntryRow.tableName,
            where: PlaylistEntryRow.Properties.playlistID == playlistID.uuidString,
            orderBy: [PlaylistEntryRow.Properties.position.order(.ascending)]
        )
    }

    private func savePlaylistEntries(_ rows: [PlaylistEntryRow], playlistID: UUID) throws {
        try database.run(transaction: { _ in
            try database.delete(
                fromTable: PlaylistEntryRow.tableName,
                where: PlaylistEntryRow.Properties.playlistID == playlistID.uuidString
            )
            for (index, var row) in rows.enumerated() {
                row.position = index
                try database.insert(row, intoTable: PlaylistEntryRow.tableName)
            }
            guard var playlist: PlaylistRow = try database.getObject(
                fromTable: PlaylistRow.tableName,
                where: PlaylistRow.Properties.playlistID == playlistID.uuidString
            ) else {
                return
            }
            playlist.updatedAt = .init()
            try database.insertOrReplace(playlist, intoTable: PlaylistRow.tableName)
        })
    }

    private func makePlaylist(from row: PlaylistRow) throws -> Playlist {
        let entryRows: [PlaylistEntryRow] = try database.getObjects(
            fromTable: PlaylistEntryRow.tableName,
            where: PlaylistEntryRow.Properties.playlistID == row.playlistID,
            orderBy: [PlaylistEntryRow.Properties.position.order(.ascending)]
        )
        return row.toModel(entries: entryRows.map { $0.toModel() })
    }

    private func metaString(for key: String) throws -> String? {
        let row: StateMetaRow? = try database.getObject(
            fromTable: StateMetaRow.tableName,
            where: StateMetaRow.Properties.key == key
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
            StateMetaRow(key: key, value: value),
            intoTable: StateMetaRow.tableName
        )
    }
}
