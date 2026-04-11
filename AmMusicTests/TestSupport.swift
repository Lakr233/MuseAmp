@testable import AmMusic
import AmMusicDatabaseKit
import Foundation

final class TestLibrarySandbox {
    let baseDirectory: URL

    init() {
        baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AmMusicTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: baseDirectory,
            withIntermediateDirectories: true,
            attributes: nil,
        )
    }

    deinit {
        try? FileManager.default.removeItem(at: baseDirectory)
    }

    func makeEnvironment() -> AppEnvironment {
        AppEnvironment(baseDirectory: baseDirectory)
    }

    func makeDatabase(
        inspectAudioFile: (@Sendable (URL) async throws -> AudioFileInspection)? = nil,
    ) throws -> MusicLibraryDatabase {
        let paths = LibraryPaths(baseDirectory: baseDirectory)
        try paths.ensureDirectoriesExist()
        let inspect: @Sendable (URL) async throws -> AudioFileInspection = inspectAudioFile ?? { url in
            let trackID = url.deletingPathExtension().lastPathComponent
            let albumID = url.deletingLastPathComponent().lastPathComponent.nilIfEmpty ?? "unknown"
            return AudioFileInspection(
                metadata: ImportedTrackMetadata(
                    trackID: trackID,
                    albumID: albumID,
                    title: trackID,
                    artistName: "Artist",
                    albumTitle: albumID,
                    sourceKind: .unknown,
                ),
                embeddedArtwork: nil,
            )
        }
        let manager = DatabaseManager(
            baseDirectory: baseDirectory,
            dependencies: RuntimeDependencies(
                resolveDownloadURL: { _ in
                    URL(fileURLWithPath: "/dev/null")
                },
                requestHeaders: { _ in [:] },
                fetchLyrics: { _ in nil },
                fetchArtworkData: { _ in nil },
                inspectAudioFile: inspect,
                setScreenAwake: { _ in },
            ),
            logSink: nil,
        )
        try manager.initializeSynchronously()
        return MusicLibraryDatabase(databaseManager: manager, paths: paths)
    }

    func makePlaylistStore() throws -> PlaylistStore {
        let database = try makeDatabase()
        return PlaylistStore(database: database)
    }
}

func makeMockTrack(
    trackID: String = "track-1",
    relativePath: String = "Artist/Album/Track 1.m4a",
    title: String = "Track 1",
    artistName: String = "Artist",
    albumTitle: String = "Album",
    fileSizeBytes: Int64 = 1024,
) -> AudioTrackRecord {
    AudioTrackRecord(
        trackID: trackID,
        albumID: "album-1",
        fileExtension: "m4a",
        relativePath: relativePath,
        fileSizeBytes: fileSizeBytes,
        fileModifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
        durationSeconds: 213,
        title: title,
        artistName: artistName,
        albumTitle: albumTitle,
        albumArtistName: artistName,
        trackNumber: 1,
        discNumber: 1,
        genreName: "Pop",
        composerName: "Composer",
        releaseDate: "2024-01-01",
        hasEmbeddedLyrics: true,
        hasEmbeddedArtwork: true,
        sourceKind: .unknown,
        createdAt: Date(),
        updatedAt: Date(),
    )
}

extension TestLibrarySandbox {
    func makeIncomingAudioFile(
        name: String = "\(UUID().uuidString).m4a",
        size: Int = 16,
    ) throws -> URL {
        let url = baseDirectory.appendingPathComponent(name, isDirectory: false)
        try Data(repeating: 0xAB, count: max(size, 1)).write(to: url, options: .atomic)
        return url
    }

    @discardableResult
    func ingestTrack(
        _ track: AudioTrackRecord,
        into database: MusicLibraryDatabase,
    ) async throws -> AudioTrackRecord {
        let incomingURL = try makeIncomingAudioFile(
            name:
            "\(track.trackID).\(URL(fileURLWithPath: track.relativePath).pathExtension.nilIfEmpty ?? "m4a")",
            size: Int(max(track.fileSizeBytes, 1)),
        )
        let metadata = ImportedTrackMetadata(
            trackID: track.trackID,
            albumID: track.albumID,
            title: track.title,
            artistName: track.artistName,
            albumTitle: track.albumTitle,
            albumArtistName: track.albumArtistName,
            durationSeconds: track.durationSeconds,
            trackNumber: track.trackNumber,
            discNumber: track.discNumber,
            genreName: track.genreName,
            composerName: track.composerName,
            releaseDate: track.releaseDate,
            lyrics: nil,
            sourceKind: .unknown,
        )
        return try await database.ingestAudioFile(url: incomingURL, metadata: metadata)
    }
}

func makeMockDownloadRecord(
    id: String = "download-1",
    title: String = "Track 1",
    state: DownloadJobStatus = .queued,
    progress: Double = 0,
) -> DownloadJob {
    DownloadJob(
        jobID: id,
        trackID: "track-1",
        albumID: "album-1",
        targetRelativePath: "Artist/Album/Track 1.m4a",
        sourceURL: "https://example.com/audio.m4a",
        title: title,
        artistName: "Artist",
        albumTitle: "Album",
        artworkURL: "https://example.com/artwork.jpg",
        status: state,
        progress: progress,
        retryCount: 0,
        errorMessage: nil,
        createdAt: Date(),
        updatedAt: Date(),
    )
}

func makeMockPlaylistEntry(
    trackID: String,
    title: String,
) -> PlaylistEntry {
    PlaylistEntry(
        trackID: trackID,
        title: title,
        artistName: "Artist",
        artworkURL: "https://example.com/\(trackID).jpg",
    )
}

func sendDatabaseCommand(
    _ database: MusicLibraryDatabase,
    _ command: LibraryCommand,
) async throws -> LibraryCommandResult {
    try await database.databaseManager.send(command)
}

extension MusicLibraryDatabase {
    func createPlaylist(name: String) async throws -> AmMusicDatabaseKit.Playlist {
        let result = try await sendDatabaseCommand(self, .createPlaylist(name: name))
        guard case let .createdPlaylist(playlist) = result else {
            throw NSError(domain: "TestSupport", code: 1)
        }
        return playlist
    }

    func fetchPlaylists() throws -> [AmMusicDatabaseKit.Playlist] {
        try databaseManager.fetchPlaylists()
    }

    func fetchPlaylist(id: UUID) throws -> AmMusicDatabaseKit.Playlist? {
        try databaseManager.fetchPlaylist(id: id)
    }

    func renamePlaylist(id: UUID, name: String) async throws {
        _ = try await sendDatabaseCommand(self, .renamePlaylist(id: id, name: name))
    }

    func deletePlaylist(id: UUID) async throws {
        _ = try await sendDatabaseCommand(self, .deletePlaylist(id: id))
    }

    func addEntry(_ entry: PlaylistEntry, to playlistID: UUID) async throws {
        _ = try await sendDatabaseCommand(
            self,
            .addPlaylistEntry(entry, playlistID: playlistID),
        )
    }

    func moveSong(in playlistID: UUID, from source: Int, to destination: Int) async throws {
        _ = try await sendDatabaseCommand(
            self,
            .movePlaylistEntry(playlistID: playlistID, from: source, to: destination),
        )
    }

    func removeSong(at index: Int, from playlistID: UUID) async throws {
        _ = try await sendDatabaseCommand(
            self,
            .removePlaylistEntry(index: index, playlistID: playlistID),
        )
    }

    func updateSongLyrics(_ lyrics: String, trackID: String, playlistID: UUID) async throws {
        _ = try await sendDatabaseCommand(
            self,
            .updateEntryLyrics(lyrics: lyrics, trackID: trackID, playlistID: playlistID),
        )
    }

    func playlistItemCount(for playlistID: UUID) throws -> Int {
        try fetchPlaylist(id: playlistID)?.entries.count ?? 0
    }
}

extension AudioFileImporter {
    convenience init(
        paths: LibraryPaths,
        database: MusicLibraryDatabase,
        metadataReader: EmbeddedMetadataReader,
        libraryIndexer _: SongLibraryIndexer,
        apiClient: APIClient,
    ) {
        self.init(
            paths: paths,
            database: database,
            metadataReader: metadataReader,
            apiClient: apiClient,
        )
    }
}
