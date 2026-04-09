import Foundation

public struct AuditSnapshot: Sendable, Codable, Hashable {
    public struct DatabaseInfo: Sendable, Codable, Hashable {
        public let path: String
        public let sizeBytes: Int64
        public let schemaVersion: Int?
        public let formatVersion: Int?

        public init(path: String, sizeBytes: Int64, schemaVersion: Int?, formatVersion: Int?) {
            self.path = path
            self.sizeBytes = sizeBytes
            self.schemaVersion = schemaVersion
            self.formatVersion = formatVersion
        }
    }

    public struct Counts: Sendable, Codable, Hashable {
        public let tracks: Int
        public let albums: Int
        public let playlists: Int
        public let playlistEntries: Int
        public let activeDownloads: Int
        public let failedDownloads: Int
        public let artworkFiles: Int
        public let lyricsFiles: Int

        public init(
            tracks: Int,
            albums: Int,
            playlists: Int,
            playlistEntries: Int,
            activeDownloads: Int,
            failedDownloads: Int,
            artworkFiles: Int,
            lyricsFiles: Int
        ) {
            self.tracks = tracks
            self.albums = albums
            self.playlists = playlists
            self.playlistEntries = playlistEntries
            self.activeDownloads = activeDownloads
            self.failedDownloads = failedDownloads
            self.artworkFiles = artworkFiles
            self.lyricsFiles = lyricsFiles
        }
    }

    public let indexDatabase: DatabaseInfo
    public let stateDatabase: DatabaseInfo
    public let counts: Counts
    public let invalidPathsFound: Int
    public let orphanArtworkFiles: Int
    public let orphanLyricsFiles: Int
    public let stagedTempFiles: Int
    public let unresolvedPlaylistEntries: Int
    public let stateIndexVersionMismatch: Bool
    public let currentIndexSchemaVersion: Int
    public let currentIndexFormatVersion: Int
    public let currentStateSchemaVersion: Int
    public let lastRebuildSucceeded: Bool
    public let lastRebuildTimestamp: Date?
    public let issues: [AuditIssue]

    public init(
        indexDatabase: DatabaseInfo,
        stateDatabase: DatabaseInfo,
        counts: Counts,
        invalidPathsFound: Int,
        orphanArtworkFiles: Int,
        orphanLyricsFiles: Int,
        stagedTempFiles: Int,
        unresolvedPlaylistEntries: Int,
        stateIndexVersionMismatch: Bool,
        currentIndexSchemaVersion: Int,
        currentIndexFormatVersion: Int,
        currentStateSchemaVersion: Int,
        lastRebuildSucceeded: Bool,
        lastRebuildTimestamp: Date?,
        issues: [AuditIssue]
    ) {
        self.indexDatabase = indexDatabase
        self.stateDatabase = stateDatabase
        self.counts = counts
        self.invalidPathsFound = invalidPathsFound
        self.orphanArtworkFiles = orphanArtworkFiles
        self.orphanLyricsFiles = orphanLyricsFiles
        self.stagedTempFiles = stagedTempFiles
        self.unresolvedPlaylistEntries = unresolvedPlaylistEntries
        self.stateIndexVersionMismatch = stateIndexVersionMismatch
        self.currentIndexSchemaVersion = currentIndexSchemaVersion
        self.currentIndexFormatVersion = currentIndexFormatVersion
        self.currentStateSchemaVersion = currentStateSchemaVersion
        self.lastRebuildSucceeded = lastRebuildSucceeded
        self.lastRebuildTimestamp = lastRebuildTimestamp
        self.issues = issues
    }
}
