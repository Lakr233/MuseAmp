//
//  DatabaseIntegrityTests.swift
//  AmMusicDatabaseKit
//
//  Created by @Lakr233 on 2026/04/11.
//

import AmMusicDatabaseKit
import Foundation
import Testing

@Suite(.serialized)
struct DatabaseIntegrityTests {
    @Test
    func `Index reset preserves state database records`() async throws {
        let fixture = try DatabaseIntegrityFixture()
        defer { try? fixture.cleanup() }

        do {
            let manager = await fixture.makeManager()
            try await manager.initialize()

            let playlist = try await createPlaylist(named: "State Playlist", manager: manager)
            let entry = PlaylistEntry(
                trackID: "state-track",
                title: "Snapshot Title",
                artistName: "Snapshot Artist",
                albumID: "state-album",
                albumTitle: "Snapshot Album",
            )
            _ = try await manager.send(.addPlaylistEntry(entry, playlistID: playlist.id))

            let request = DownloadRequest(
                trackID: "queued-track",
                albumID: "state-album",
                title: "Queued Track",
                artistName: "Queue Artist",
            )
            _ = try await manager.send(.enqueueDownloads([request]))

            let sourceURL = try fixture.createIncomingAudioFile()
            let metadata = ImportedTrackMetadata(
                trackID: "state-track",
                albumID: "state-album",
                title: "Library Title",
                artistName: "Library Artist",
                albumTitle: "Library Album",
                sourceKind: .downloaded,
            )
            await fixture.setInspectionMetadata(metadata)
            _ = try await manager.send(.ingestAudioFile(url: sourceURL, metadata: metadata))

            let queuedBeforeReset = try manager.activeDownloads()
            #expect(queuedBeforeReset.count == 1)
        }

        try fixture.removeIndexDatabaseArtifacts()

        let reloadedManager = await fixture.makeManager()
        try await reloadedManager.initialize()

        let playlistsAfterReset = try reloadedManager.fetchPlaylists()
        #expect(playlistsAfterReset.count == 1)
        #expect(playlistsAfterReset.first?.entries.count == 1)
        #expect(playlistsAfterReset.first?.entries.first?.title == "Snapshot Title")

        let queuedAfterReset = try reloadedManager.activeDownloads()
        #expect(queuedAfterReset.map(\.trackID) == ["queued-track"])

        let tracksBeforeRebuild = try reloadedManager.searchTracks(
            query: "Library Title", limit: 10,
        )
        #expect(tracksBeforeRebuild.isEmpty)

        let rebuildResult = try await reloadedManager.send(.rebuildIndex(pruneInvalidFiles: true))
        guard case let .rebuild(scanned, upserted, deleted) = rebuildResult else {
            Issue.record("Expected rebuild result after index reset")
            return
        }
        #expect(scanned == 1)
        #expect(upserted == 1)
        #expect(deleted == 0)

        let restoredTracks = try reloadedManager.searchTracks(query: "Library Title", limit: 10)
        #expect(restoredTracks.count == 1)
    }

    @Test
    func `Rebuild prunes invalid files and reconciles stale rows`() async throws {
        let fixture = try DatabaseIntegrityFixture()
        defer { try? fixture.cleanup() }

        let manager = await fixture.makeManager()
        try await manager.initialize()

        _ = try fixture.createLibraryAudioFile(relativePath: "album-a/good-track.m4a")
        let invalidAtRoot = try fixture.createLibraryAudioFile(relativePath: "orphan.m4a")
        let tempResidue = try fixture.createLibraryAudioFile(relativePath: "album-a/temp-track.m4a.tmp")
        let unreadable = try fixture.createLibraryAudioFile(relativePath: "album-b/bad-track.m4a")
        await fixture.setInspectionFailure(trackID: "bad-track", enabled: true)

        let firstRebuild = try await manager.send(.rebuildIndex(pruneInvalidFiles: true))
        guard case let .rebuild(scanned, upserted, deleted) = firstRebuild else {
            Issue.record("Expected rebuild result")
            return
        }
        #expect(scanned == 4)
        #expect(upserted == 1)
        #expect(deleted == 0)

        #expect(!FileManager.default.fileExists(atPath: invalidAtRoot.path))
        #expect(!FileManager.default.fileExists(atPath: tempResidue.path))
        #expect(!FileManager.default.fileExists(atPath: unreadable.path))

        let indexedTracks = try manager.searchTracks(query: "good-track", limit: 10)
        #expect(indexedTracks.count == 1)
        #expect(indexedTracks.first?.trackID == "good-track")

        let validPath = fixture.paths.audioDirectory.appendingPathComponent("album-a/good-track.m4a")
        try FileManager.default.removeItem(at: validPath)

        let secondRebuild = try await manager.send(.rebuildIndex(pruneInvalidFiles: true))
        guard case let .rebuild(secondScanned, secondUpserted, secondDeleted) = secondRebuild
        else {
            Issue.record("Expected rebuild result")
            return
        }
        #expect(secondScanned == 0)
        #expect(secondUpserted == 0)
        #expect(secondDeleted == 1)

        let tracksAfterDeletion = try manager.searchTracks(query: "good-track", limit: 10)
        #expect(tracksAfterDeletion.isEmpty)
    }

    @Test
    func `Playlist entries keep snapshot metadata after track changes`() async throws {
        let fixture = try DatabaseIntegrityFixture()
        defer { try? fixture.cleanup() }

        let manager = await fixture.makeManager()
        try await manager.initialize()

        let playlist = try await createPlaylist(named: "Snapshot Playlist", manager: manager)
        let firstFile = try fixture.createIncomingAudioFile(name: "snapshot-track.m4a")
        let firstMetadata = ImportedTrackMetadata(
            trackID: "snapshot-track",
            albumID: "snapshot-album",
            title: "First Library Title",
            artistName: "First Artist",
            albumTitle: "Snapshot Album",
            sourceKind: .downloaded,
        )
        _ = try await manager.send(.ingestAudioFile(url: firstFile, metadata: firstMetadata))

        let snapshotEntry = PlaylistEntry(
            trackID: "snapshot-track",
            title: "First Library Title",
            artistName: "First Artist",
            albumID: "snapshot-album",
            albumTitle: "Snapshot Album",
        )
        _ = try await manager.send(.addPlaylistEntry(snapshotEntry, playlistID: playlist.id))

        let secondFile = try fixture.createIncomingAudioFile(name: "snapshot-track-update.m4a")
        let secondMetadata = ImportedTrackMetadata(
            trackID: "snapshot-track",
            albumID: "snapshot-album",
            title: "Updated Library Title",
            artistName: "Updated Artist",
            albumTitle: "Snapshot Album",
            sourceKind: .downloaded,
        )
        _ = try await manager.send(.ingestAudioFile(url: secondFile, metadata: secondMetadata))

        let playlistAfterUpdate = try manager.fetchPlaylist(id: playlist.id)
        #expect(playlistAfterUpdate?.entries.count == 1)
        #expect(playlistAfterUpdate?.entries.first?.title == "First Library Title")
        #expect(playlistAfterUpdate?.entries.first?.artistName == "First Artist")

        let albumTracks = try manager.tracks(inAlbumID: "snapshot-album")
        #expect(albumTracks.count == 1)
        #expect(albumTracks.first?.title == "Updated Library Title")
        #expect(albumTracks.first?.artistName == "Updated Artist")
    }

    @Test
    func `Removing tracks or albums keeps playlist snapshot entries`() async throws {
        let fixture = try DatabaseIntegrityFixture()
        defer { try? fixture.cleanup() }

        let manager = await fixture.makeManager()
        try await manager.initialize()

        let playlist = try await createPlaylist(named: "Remove Semantics", manager: manager)

        let firstFile = try fixture.createIncomingAudioFile(name: "remove-track-1.m4a")
        let firstMetadata = ImportedTrackMetadata(
            trackID: "remove-track-1",
            albumID: "remove-album",
            title: "Remove Track 1",
            artistName: "Remove Artist",
            albumTitle: "Remove Album",
            sourceKind: .downloaded,
        )
        _ = try await manager.send(.ingestAudioFile(url: firstFile, metadata: firstMetadata))

        let secondFile = try fixture.createIncomingAudioFile(name: "remove-track-2.m4a")
        let secondMetadata = ImportedTrackMetadata(
            trackID: "remove-track-2",
            albumID: "remove-album",
            title: "Remove Track 2",
            artistName: "Remove Artist",
            albumTitle: "Remove Album",
            sourceKind: .downloaded,
        )
        _ = try await manager.send(.ingestAudioFile(url: secondFile, metadata: secondMetadata))

        let firstEntry = PlaylistEntry(
            trackID: "remove-track-1",
            title: "Snapshot Remove 1",
            artistName: "Snapshot Artist",
            albumID: "remove-album",
            albumTitle: "Remove Album",
        )
        let secondEntry = PlaylistEntry(
            trackID: "remove-track-2",
            title: "Snapshot Remove 2",
            artistName: "Snapshot Artist",
            albumID: "remove-album",
            albumTitle: "Remove Album",
        )
        _ = try await manager.send(.addPlaylistEntry(firstEntry, playlistID: playlist.id))
        _ = try await manager.send(.addPlaylistEntry(secondEntry, playlistID: playlist.id))

        _ = try await manager.send(.removeTrack(trackID: "remove-track-1"))
        let tracksAfterTrackRemoval = try manager.tracks(inAlbumID: "remove-album")
        #expect(tracksAfterTrackRemoval.map(\.trackID) == ["remove-track-2"])

        let playlistAfterTrackRemoval = try manager.fetchPlaylist(id: playlist.id)
        #expect(
            playlistAfterTrackRemoval?.entries.map(\.trackID) == ["remove-track-1", "remove-track-2"],
        )

        _ = try await manager.send(.removeAlbum(albumID: "remove-album"))
        let tracksAfterAlbumRemoval = try manager.tracks(inAlbumID: "remove-album")
        #expect(tracksAfterAlbumRemoval.isEmpty)

        let albumDirectory = fixture.paths.audioDirectory.appendingPathComponent(
            "remove-album", isDirectory: true,
        )
        #expect(!FileManager.default.fileExists(atPath: albumDirectory.path))

        let playlistAfterAlbumRemoval = try manager.fetchPlaylist(id: playlist.id)
        #expect(
            playlistAfterAlbumRemoval?.entries.map(\.trackID) == ["remove-track-1", "remove-track-2"],
        )
        #expect(
            playlistAfterAlbumRemoval?.entries.map(\.title) == ["Snapshot Remove 1", "Snapshot Remove 2"],
        )
    }

    private func createPlaylist(named name: String, manager: DatabaseManager) async throws -> Playlist {
        let result = try await manager.send(.createPlaylist(name: name))
        guard case let .createdPlaylist(playlist) = result else {
            Issue.record("Expected createdPlaylist result")
            throw TestFailure.unexpectedCommandResult
        }
        return playlist
    }
}

private enum TestFailure: Error {
    case unexpectedCommandResult
}
