//
//  TrackTagTests.swift
//  MuseAmpDatabaseKit
//
//  Created by @Lakr233 on 2026/10/03.
//

import Foundation
import MuseAmpDatabaseKit
import SQLite3
import Testing

struct AlbumOrderTests {
    private func track(_ trackID: String, title: String, track: Int?, disc: Int?) -> AudioTrackRecord {
        AudioTrackRecord(
            trackID: trackID,
            albumID: "album",
            fileExtension: "m4a",
            relativePath: "album/\(trackID).m4a",
            fileSizeBytes: 1,
            fileModifiedAt: .init(timeIntervalSince1970: 0),
            durationSeconds: 60,
            title: title,
            artistName: "Artist",
            albumTitle: "Album",
            trackNumber: track,
            discNumber: disc,
        )
    }

    @Test
    func `album order is disc, then track, then title`() {
        let tracks = [
            track("a", title: "Alpha", track: 1, disc: 2),
            track("z", title: "Zulu", track: 1, disc: 1),
            track("y", title: "Yankee", track: 2, disc: 1),
            track("b", title: "Bravo", track: 2, disc: 2),
        ]
        #expect(tracks.sortedInAlbumOrder().map(\.title) == ["Zulu", "Yankee", "Alpha", "Bravo"])
    }

    @Test
    func `numbered tracks come before unnumbered ones, titles sort naturally`() {
        let tracks = [
            track("t10", title: "Track 10", track: nil, disc: nil),
            track("t2", title: "Track 2", track: nil, disc: nil),
            track("n3", title: "Numbered", track: 3, disc: nil),
            track("d1", title: "Disc One", track: nil, disc: 1),
        ]
        #expect(tracks.sortedInAlbumOrder().map(\.trackID) == ["d1", "n3", "t2", "t10"])
    }
}

@Suite(.serialized)
struct TrackTagBackfillTests {
    @Test
    func `index that only filled album artists still gets track and disc numbers`() async throws {
        let fixture = try DatabaseIntegrityFixture()
        defer { try? fixture.cleanup() }
        let manager = await fixture.makeManager()
        try await manager.initialize()

        for (index, trackID) in ["9401", "9402"].enumerated() {
            _ = try fixture.createLibraryAudioFile(relativePath: "940/\(trackID).m4a")
            await fixture.setInspectionMetadata(ImportedTrackMetadata(
                trackID: trackID,
                albumID: "940",
                title: "Title \(index)",
                artistName: "Artist",
                albumTitle: "Album",
                albumArtistName: "Album Artist",
                sourceKind: .imported,
            ))
        }
        _ = try await manager.send(.rebuildIndex(pruneInvalidFiles: false))
        // The marker the album-artist-only backfill (version 1) left behind.
        try setIndexMeta(key: "album_artist_backfill_version", value: "1", in: fixture.paths.indexDatabaseURL)

        let updated = try await manager.backfillTrackTagsIfNeeded { url in
            let trackID = url.deletingPathExtension().lastPathComponent
            return TrackTags(albumArtistName: "Ignored", trackNumber: trackID == "9401" ? 2 : 1, discNumber: 1)
        }

        #expect(updated == 2)
        let tracks = try manager.tracks(inAlbumID: "940")
        #expect(tracks.map(\.trackID) == ["9402", "9401"])
        #expect(tracks.map(\.trackNumber) == [1, 2])
        #expect(tracks.allSatisfy { $0.discNumber == 1 && $0.albumArtistName == "Album Artist" })
        let rerun = try await manager.backfillTrackTagsIfNeeded { _ in TrackTags(trackNumber: 9) }
        #expect(rerun == 0)
    }

    private func setIndexMeta(key: String, value: String, in databaseURL: URL) throws {
        var database: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &database) == SQLITE_OK else {
            sqlite3_close(database)
            throw CocoaError(.fileReadUnknown)
        }
        defer { sqlite3_close(database) }
        let sql = "INSERT OR REPLACE INTO index_meta (key, value) VALUES ('\(key)', '\(value)')"
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}
