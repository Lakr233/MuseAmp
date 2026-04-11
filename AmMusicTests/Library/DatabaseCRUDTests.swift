@testable import AmMusic
import AmMusicDatabaseKit
import Foundation
import Testing

@Suite(.serialized)
struct DatabaseCRUDTests {
    @Test
    func `Database tables support full CRUD`() async throws {
        try await tracksCRUD()
        try downloadRecordsCRUD()
        try await playlistsCRUD()
        try await playlistItemsCRUD()
    }

    @Test
    func `Database groups tracks into local albums`() async throws {
        let sandbox = TestLibrarySandbox()
        let database = try sandbox.makeDatabase()

        let firstAlbumTrack1 = AudioTrackRecord(
            trackID: "track-a1",
            albumID: "unknown",
            fileExtension: "m4a",
            relativePath: "Artist/Album A/02 Track.m4a",
            fileSizeBytes: 1024,
            fileModifiedAt: Date(timeIntervalSince1970: 200),
            durationSeconds: 200,
            title: "Track 2",
            artistName: "Artist",
            albumTitle: "Album A",
            albumArtistName: "Artist",
            trackNumber: 2,
            discNumber: 1,
            sourceKind: .unknown,
            createdAt: Date(),
            updatedAt: Date(),
        )
        let firstAlbumTrack2 = AudioTrackRecord(
            trackID: "track-a2",
            albumID: "unknown",
            fileExtension: "m4a",
            relativePath: "Artist/Album A/01 Track.m4a",
            fileSizeBytes: 1024,
            fileModifiedAt: Date(timeIntervalSince1970: 300),
            durationSeconds: 180,
            title: "Track 1",
            artistName: "Artist",
            albumTitle: "Album A",
            albumArtistName: "Artist",
            trackNumber: 1,
            discNumber: 1,
            hasEmbeddedArtwork: true,
            sourceKind: .unknown,
            createdAt: Date(),
            updatedAt: Date(),
        )
        let secondAlbumTrack = AudioTrackRecord(
            trackID: "track-b1",
            albumID: "album-b",
            fileExtension: "m4a",
            relativePath: "Artist/Album B/Track 1.m4a",
            fileSizeBytes: 1024,
            fileModifiedAt: Date(timeIntervalSince1970: 100),
            durationSeconds: 220,
            title: "Track 1",
            artistName: "Artist",
            albumTitle: "Album B",
            albumArtistName: "Artist",
            trackNumber: 1,
            discNumber: 1,
            sourceKind: .unknown,
            createdAt: Date(),
            updatedAt: Date(),
        )

        try await sandbox.ingestTrack(firstAlbumTrack1, into: database)
        try await sandbox.ingestTrack(firstAlbumTrack2, into: database)
        try await sandbox.ingestTrack(secondAlbumTrack, into: database)

        let albums = try database.allAlbums()

        #expect(albums.count == 2)
        let albumA = try #require(albums.first(where: { $0.albumTitle == "Album A" }))
        #expect(albumA.albumID == "unknown")
        #expect(albumA.trackCount == 2)

        let albumB = try #require(albums.first(where: { $0.albumTitle == "Album B" }))
        #expect(albumB.albumID == "album-b")
        #expect(albumB.trackCount == 1)
    }

    private func tracksCRUD() async throws {
        let sandbox = TestLibrarySandbox()
        let database = try sandbox.makeDatabase()

        let created = makeMockTrack()
        let insertedTrack = try await sandbox.ingestTrack(created, into: database)

        let inserted = try database.allTracks()
        #expect(inserted.count == 1)
        #expect(inserted.first?.trackID == created.trackID)
        #expect(inserted.first?.title == "Track 1")

        let updated = makeMockTrack(
            trackID: created.trackID,
            relativePath: created.relativePath,
            title: "Track 1 (Updated)",
            artistName: "Artist",
            albumTitle: "Album",
            fileSizeBytes: 2048,
        )
        try await sandbox.ingestTrack(updated, into: database)

        let fetchedUpdated = try database.allTracks()
        #expect(fetchedUpdated.count == 1)
        #expect(fetchedUpdated.first?.title == "Track 1 (Updated)")
        #expect(fetchedUpdated.first?.fileSizeBytes == 2048)

        try await database.deleteTracks(relativePaths: [insertedTrack.relativePath])
        let remainingTracks = try database.allTracks()
        #expect(remainingTracks.isEmpty)
    }

    private func downloadRecordsCRUD() throws {
        let sandbox = TestLibrarySandbox()
        let database = try sandbox.makeDatabase()

        let created = makeMockDownloadRecord()
        try database.upsertDownloadJob(created)

        let inserted = try database.downloadJob(id: created.jobID)
        #expect(inserted?.jobID == created.jobID)
        let activeJobsAfterInsert = try database.activeDownloadJobs()
        #expect(activeJobsAfterInsert.count == 1)

        let updated = DownloadJob(
            jobID: created.jobID,
            trackID: created.trackID,
            albumID: created.albumID,
            targetRelativePath: created.targetRelativePath,
            sourceURL: created.sourceURL,
            title: created.title,
            artistName: created.artistName,
            albumTitle: created.albumTitle,
            artworkURL: created.artworkURL,
            status: .failed,
            progress: 1,
            retryCount: created.retryCount,
            errorMessage: created.errorMessage,
            createdAt: created.createdAt,
            updatedAt: Date(),
        )
        try database.upsertDownloadJob(updated)

        let fetchedUpdated = try database.downloadJob(id: created.jobID)
        #expect(fetchedUpdated != nil)
        let activeJobsAfterUpdate = try database.activeDownloadJobs()
        #expect(activeJobsAfterUpdate.isEmpty)

        try database.deleteDownloadRecords(trackIDs: [created.trackID])
        let remainingJobs = try database.allDownloadJobs()
        #expect(remainingJobs.isEmpty)
    }

    private func playlistsCRUD() async throws {
        let sandbox = TestLibrarySandbox()
        let database = try sandbox.makeDatabase()

        let created = try await database.createPlaylist(name: "Focus")
        let inserted = try database.fetchPlaylist(id: created.id)
        #expect(inserted?.name == "Focus")
        let playlistsAfterCreate = try database.fetchPlaylists()
        #expect(playlistsAfterCreate.count == 1)

        _ = try await sendDatabaseCommand(database, .renamePlaylist(id: created.id, name: "Deep Focus"))
        let updated = try database.fetchPlaylist(id: created.id)
        #expect(updated?.name == "Deep Focus")

        _ = try await sendDatabaseCommand(database, .deletePlaylist(id: created.id))
        let playlistsAfterDelete = try database.fetchPlaylists()
        #expect(playlistsAfterDelete.isEmpty)
        let deleted = try database.fetchPlaylist(id: created.id)
        #expect(deleted?.id == nil)
    }

    private func playlistItemsCRUD() async throws {
        let sandbox = TestLibrarySandbox()
        let database = try sandbox.makeDatabase()
        let playlist = try await database.createPlaylist(name: "Queue")

        _ = try await sendDatabaseCommand(
            database,
            .addPlaylistEntry(makeMockPlaylistEntry(trackID: "song-a", title: "Song A"), playlistID: playlist.id),
        )
        _ = try await sendDatabaseCommand(
            database,
            .addPlaylistEntry(makeMockPlaylistEntry(trackID: "song-b", title: "Song B"), playlistID: playlist.id),
        )

        let insertedPlaylist = try database.fetchPlaylist(id: playlist.id)
        let inserted = try #require(insertedPlaylist)
        #expect(inserted.entries.map(\.trackID) == ["song-a", "song-b"])

        _ = try await sendDatabaseCommand(database, .movePlaylistEntry(playlistID: playlist.id, from: 1, to: 0))
        let movedPlaylist = try database.fetchPlaylist(id: playlist.id)
        let moved = try #require(movedPlaylist)
        #expect(moved.entries.map(\.trackID) == ["song-b", "song-a"])

        _ = try await sendDatabaseCommand(database, .removePlaylistEntry(index: 0, playlistID: playlist.id))
        let deletedPlaylist = try database.fetchPlaylist(id: playlist.id)
        let deleted = try #require(deletedPlaylist)
        #expect(deleted.entries.map(\.trackID) == ["song-a"])
    }
}
