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

    @Test
    func `numbers read from TRACKTOTAL and DISCTOTAL are repaired, others stay`() async throws {
        let fixture = try DatabaseIntegrityFixture()
        defer { try? fixture.cleanup() }
        let manager = await fixture.makeManager()
        try await manager.initialize()

        // What older builds stored: the substring match read TRACKTOTAL and
        // DISCTOTAL as the position for 9501 and 9504.
        let stored: [(trackID: String, track: Int?, disc: Int?)] = [
            ("9501", 13, 2), // PR #12 file: TRACKTOTAL 13, trkn 3; DISCTOTAL 2, disk 1
            ("9502", 13, nil), // track 13 of 13: trkn 13, TRACKTOTAL 13
            ("9503", 13, nil), // TRACKTOTAL 13 but no position in the file
            ("9504", 5, nil), // stored 5 is not the total: kept even though trkn says 3
        ]
        for track in stored {
            _ = try fixture.createLibraryAudioFile(relativePath: "950/\(track.trackID).m4a")
            await fixture.setInspectionMetadata(ImportedTrackMetadata(
                trackID: track.trackID,
                albumID: "950",
                title: "Title \(track.trackID)",
                artistName: "Artist",
                albumTitle: "Album",
                albumArtistName: "Album Artist",
                trackNumber: track.track,
                discNumber: track.disc,
                sourceKind: .imported,
            ))
        }
        _ = try await manager.send(.rebuildIndex(pruneInvalidFiles: false))

        let fileTags: [String: TrackTags] = [
            "9501": TrackTags(trackNumber: 3, discNumber: 1, trackTotal: 13, discTotal: 2),
            "9502": TrackTags(trackNumber: 13, trackTotal: 13),
            "9503": TrackTags(trackTotal: 13),
            "9504": TrackTags(trackNumber: 3, trackTotal: 13),
        ]
        let updated = try await manager.backfillTrackTagsIfNeeded { url in
            fileTags[url.deletingPathExtension().lastPathComponent] ?? TrackTags()
        }

        #expect(updated == 1)
        let after = try Dictionary(uniqueKeysWithValues: manager.tracks(inAlbumID: "950").map { ($0.trackID, $0) })
        #expect(after["9501"]?.trackNumber == 3)
        #expect(after["9501"]?.discNumber == 1)
        #expect(after["9502"]?.trackNumber == 13)
        #expect(after["9503"]?.trackNumber == 13)
        #expect(after["9504"]?.trackNumber == 5)
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
