//
//  AlbumArtistTests.swift
//  MuseAmpDatabaseKit
//
//  Created by @Lakr233 on 2026/10/03.
//

import Combine
import Foundation
import MuseAmpDatabaseKit
import Testing

struct AlbumArtistResolverTests {
    private func track(
        _ number: Int,
        artist: String,
        albumArtist: String?,
        albumID: String = "album",
    ) -> AudioTrackRecord {
        AudioTrackRecord(
            trackID: "\(albumID)-\(number)",
            albumID: albumID,
            fileExtension: "m4a",
            relativePath: "\(albumID)/\(albumID)-\(number).m4a",
            fileSizeBytes: 1,
            fileModifiedAt: .init(timeIntervalSince1970: 0),
            durationSeconds: 60,
            title: "Track \(number)",
            artistName: artist,
            albumTitle: "Example Album",
            albumArtistName: albumArtist,
            trackNumber: number,
        )
    }

    @Test
    func `issue 8 album shows its Album Artist, not the joined track artists`() {
        let tracks = [
            track(1, artist: "Artist A", albumArtist: "Artist A"),
            track(2, artist: "Artist A, Artist B", albumArtist: "Artist A"),
            track(3, artist: "Artist C", albumArtist: "Artist A"),
        ]
        #expect(AlbumArtistResolver.albumArtistName(for: tracks) == "Artist A")
        #expect(AlbumArtistResolver.taggedAlbumArtistName(for: tracks) == "Artist A")
    }

    @Test
    func `compilation tagged with an album artist keeps the tag`() {
        let tracks = [
            track(1, artist: "Singer X", albumArtist: "Various Artists"),
            track(2, artist: "Singer Y", albumArtist: "Various Artists"),
            track(3, artist: "Singer Z", albumArtist: "Various Artists"),
        ]
        #expect(AlbumArtistResolver.albumArtistName(for: tracks) == "Various Artists")
    }

    @Test
    func `untagged album by one artist shows that artist`() {
        let tracks = [
            track(1, artist: "Solo Artist", albumArtist: nil),
            track(2, artist: " solo artist ", albumArtist: nil),
            track(3, artist: "Solo Artist", albumArtist: ""),
        ]
        #expect(AlbumArtistResolver.albumArtistName(for: tracks) == "Solo Artist")
        #expect(AlbumArtistResolver.taggedAlbumArtistName(for: tracks) == nil)
    }

    @Test
    func `untagged album with mixed artists shows Various Artists`() {
        let tracks = [
            track(1, artist: "Singer X", albumArtist: nil),
            track(2, artist: "Singer Y", albumArtist: nil),
            track(3, artist: "Singer X, Singer Z", albumArtist: nil),
        ]
        let name = AlbumArtistResolver.albumArtistName(for: tracks)
        #expect(name == AlbumArtistResolver.variousArtistsName)
        #expect(name?.contains(",") == false)
    }

    @Test
    func `most common Album Artist wins and ties go to the first track`() {
        let mostCommon = [
            track(1, artist: "A", albumArtist: "Band One"),
            track(2, artist: "B", albumArtist: "Band Two"),
            track(3, artist: "C", albumArtist: "band two"),
            track(4, artist: "D", albumArtist: nil),
        ]
        #expect(AlbumArtistResolver.albumArtistName(for: mostCommon) == "Band Two")

        let tie = [
            track(2, artist: "B", albumArtist: "Band Two"),
            track(1, artist: "A", albumArtist: "Band One"),
        ]
        #expect(AlbumArtistResolver.albumArtistName(for: tie) == "Band One")
    }

    @Test
    func `album without any artist has no album artist`() {
        #expect(AlbumArtistResolver.albumArtistName(for: []) == nil)
        #expect(AlbumArtistResolver.albumArtistName(albumArtistNames: [nil], artistNames: [" "]) == nil)
    }
}

@Suite(.serialized)
struct AlbumArtistLibraryTests {
    private actor TagReader {
        private(set) var readCount = 0
        let tagsByTrackID: [String: TrackTags]

        init(tagsByTrackID: [String: TrackTags]) {
            self.tagsByTrackID = tagsByTrackID
        }

        func read(_ fileURL: URL) -> TrackTags {
            readCount += 1
            return tagsByTrackID[fileURL.deletingPathExtension().lastPathComponent] ?? TrackTags()
        }
    }

    @Test
    func `album list groups by album and shows the album-level artist`() async throws {
        let fixture = try DatabaseIntegrityFixture()
        defer { try? fixture.cleanup() }
        let manager = await fixture.makeManager()
        try await manager.initialize()

        let credits: [(trackID: String, albumID: String, artist: String, albumArtist: String?)] = [
            ("9001", "900", "Artist A", "Artist A"),
            ("9002", "900", "Artist A, Artist B", "Artist A"),
            ("9003", "900", "Artist C", "Artist A"),
            ("9101", "910", "Singer X", nil),
            ("9102", "910", "Singer Y", nil),
        ]
        for credit in credits {
            _ = try fixture.createLibraryAudioFile(relativePath: "\(credit.albumID)/\(credit.trackID).m4a")
            await fixture.setInspectionMetadata(ImportedTrackMetadata(
                trackID: credit.trackID,
                albumID: credit.albumID,
                title: "Title \(credit.trackID)",
                artistName: credit.artist,
                albumTitle: "Album \(credit.albumID)",
                albumArtistName: credit.albumArtist,
                sourceKind: .imported,
            ))
        }
        _ = try await manager.send(.rebuildIndex(pruneInvalidFiles: false))

        let albums = try Dictionary(uniqueKeysWithValues: manager.listAlbums().map { ($0.albumID, $0) })
        #expect(albums.count == 2)
        #expect(albums["900"]?.artistName == "Artist A")
        #expect(albums["900"]?.albumArtistName == "Artist A")
        #expect(albums["910"]?.artistName == AlbumArtistResolver.variousArtistsName)
        #expect(albums["910"]?.albumArtistName == nil)
    }

    @Test
    func `ingest keeps the file's Album Artist when the caller has none`() async throws {
        let fixture = try DatabaseIntegrityFixture()
        defer { try? fixture.cleanup() }
        let manager = await fixture.makeManager { _ in
            AudioFileInspection(
                metadata: ImportedTrackMetadata(
                    trackID: "9201",
                    albumID: "920",
                    title: "Tagged",
                    artistName: "Track Artist",
                    albumTitle: "Album",
                    albumArtistName: "Tagged Album Artist",
                    sourceKind: .unknown,
                ),
                embeddedArtwork: nil,
            )
        }
        try await manager.initialize()

        let download = ImportedTrackMetadata(
            trackID: "9201",
            albumID: "920",
            title: "Tagged",
            artistName: "Track Artist",
            albumTitle: "Album",
            albumArtistName: nil,
            sourceKind: .downloaded,
        )
        _ = try await manager.send(.ingestAudioFile(url: fixture.createIncomingAudioFile(), metadata: download))
        #expect(try manager.track(trackID: "9201")?.albumArtistName == "Tagged Album Artist")
    }

    @Test
    func `backfill fills missing tags once, keeps stored values and album IDs`() async throws {
        let fixture = try DatabaseIntegrityFixture()
        defer { try? fixture.cleanup() }
        let manager = await fixture.makeManager()
        try await manager.initialize()

        // Indexed the way older builds did: Album Artist, trkn and disk were
        // never read, except for values that came from elsewhere.
        let tracks: [(trackID: String, artist: String, albumArtist: String?, trackNumber: Int?)] = [
            ("9301", "Artist A", nil, nil),
            ("9302", "Artist A, Artist B", nil, nil),
            ("9303", "Artist C", nil, nil),
            ("9304", "Artist D", "Already Set", 7),
        ]
        for track in tracks {
            _ = try fixture.createLibraryAudioFile(relativePath: "930/\(track.trackID).m4a")
            await fixture.setInspectionMetadata(ImportedTrackMetadata(
                trackID: track.trackID,
                albumID: "930",
                title: "Title \(track.trackID)",
                artistName: track.artist,
                albumTitle: "Example Album",
                albumArtistName: track.albumArtist,
                trackNumber: track.trackNumber,
                sourceKind: .imported,
            ))
        }
        _ = try await manager.send(.rebuildIndex(pruneInvalidFiles: false))
        let before = try manager.tracks(inAlbumID: "930")
        #expect(before.count == 4)

        let reader = TagReader(tagsByTrackID: [
            "9301": TrackTags(albumArtistName: "Artist A", trackNumber: 1, discNumber: 1),
            "9302": TrackTags(albumArtistName: "Artist A", trackNumber: 2),
            "9304": TrackTags(albumArtistName: "Tag On Disk", trackNumber: 4, discNumber: 1),
        ])
        let events = EventRecorder(manager: manager)
        let updated = try await manager.backfillTrackTagsIfNeeded { await reader.read($0) }

        #expect(updated == 3)
        #expect(await reader.readCount == 4)
        let after = try Dictionary(uniqueKeysWithValues: manager.tracks(inAlbumID: "930").map { ($0.trackID, $0) })
        #expect(after["9301"]?.albumArtistName == "Artist A")
        #expect(after["9301"]?.trackNumber == 1)
        #expect(after["9301"]?.discNumber == 1)
        #expect(after["9302"]?.albumArtistName == "Artist A")
        #expect(after["9302"]?.trackNumber == 2)
        #expect(after["9302"]?.discNumber == nil)
        #expect(after["9303"]?.albumArtistName == nil)
        #expect(after["9303"]?.trackNumber == nil)
        // Stored values win over what the file says; only the empty disc fills.
        #expect(after["9304"]?.albumArtistName == "Already Set")
        #expect(after["9304"]?.trackNumber == 7)
        #expect(after["9304"]?.discNumber == 1)
        #expect(Set(after.values.map(\.albumID)) == ["930"])
        #expect(Set(after.values.map(\.relativePath)) == Set(before.map(\.relativePath)))
        #expect(try manager.listAlbums().first?.artistName == "Artist A")
        #expect(events.updatedTrackIDs == ["9301", "9302", "9304"])
        #expect(try manager.tracks(inAlbumID: "930").map(\.trackID) == ["9301", "9304", "9302", "9303"])

        let secondRun = try await manager.backfillTrackTagsIfNeeded { await reader.read($0) }
        #expect(secondRun == 0)
        #expect(await reader.readCount == 4)
    }
}

private final class EventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var updated: Set<String> = []
    private var cancellable: AnyCancellable?

    init(manager: DatabaseManager) {
        cancellable = manager.events.sink { [weak self] event in
            guard case let .tracksChanged(_, updated, _) = event else { return }
            self?.record(updated)
        }
    }

    var updatedTrackIDs: Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return updated
    }

    private func record(_ trackIDs: [String]) {
        lock.lock()
        defer { lock.unlock() }
        updated.formUnion(trackIDs)
    }
}
