import Foundation
@testable import MuseAmp
import Testing

struct EmbeddedTrackIdentityTests {
    @Test
    func `local IDs are stable across renames and keep catalog identity separate`() throws {
        let sandbox = TestLibrarySandbox()
        let source = sandbox.baseDirectory.appendingPathComponent("first.m4a")
        try Data(repeating: 0x42, count: 1024 * 1024 + 3).write(to: source)
        let first = try EmbeddedTrackIdentity.local(fileURL: source, album: " Album ", albumArtist: "ARTIST", artist: "Guest")
        let renamed = sandbox.baseDirectory.appendingPathComponent("renamed.m4a")
        try FileManager.default.moveItem(at: source, to: renamed)
        let second = try EmbeddedTrackIdentity.local(fileURL: renamed, album: "album", albumArtist: "artist", artist: "Other Guest")
        #expect(first == second)
        #expect(EmbeddedTrackIdentity.isTrackID(first.trackID))
        #expect(EmbeddedTrackIdentity.isAlbumID(first.albumID))
        #expect(!first.trackID.isCatalogID)
        #expect(!first.albumID.isCatalogID)

        try Data("different bytes".utf8).write(to: renamed)
        let different = try EmbeddedTrackIdentity.local(fileURL: renamed, album: "Album", albumArtist: "Artist", artist: "Guest")
        #expect(first.trackID != different.trackID)
        #expect(first.albumID == different.albumID)
    }

    @Test
    func `album identity uses album artist or track artist and isolates unassigned albums`() throws {
        let sandbox = TestLibrarySandbox()
        let source = sandbox.baseDirectory.appendingPathComponent("source.m4a")
        try Data("first".utf8).write(to: source)
        let first = try EmbeddedTrackIdentity.local(fileURL: source, album: "Album", albumArtist: nil, artist: "Artist A")
        let otherArtist = try EmbeddedTrackIdentity.local(fileURL: source, album: "Album", albumArtist: nil, artist: "Artist B")
        #expect(first.albumID != otherArtist.albumID)
        let blankAlbumArtist = try EmbeddedTrackIdentity.local(fileURL: source, album: "Album", albumArtist: "  ", artist: "Artist A")
        #expect(first.albumID == blankAlbumArtist.albumID)
        let unassigned = try EmbeddedTrackIdentity.local(fileURL: source, album: nil, albumArtist: nil, artist: "Artist A")
        try Data("second".utf8).write(to: source)
        let otherUnassigned = try EmbeddedTrackIdentity.local(fileURL: source, album: nil, albumArtist: nil, artist: "Artist A")
        #expect(unassigned.albumID != otherUnassigned.albumID)
    }

    @Test(arguments: [
        "local-track-../escape", "local-track-123", "unknown", "",
        "local-track-" + String(repeating: "g", count: 64),
        "local-album-" + String(repeating: "a", count: 64),
    ])
    func `invalid local track IDs are rejected`(_ value: String) {
        #expect(!EmbeddedTrackIdentity.isTrackID(value))
    }

    @Test(arguments: [
        "My original notes", #"Use "trackID" for reference"#, #"{"rating":5}"#,
        #"{"albumID":"third-party-id"}"#, #"{"trackID":123}"#,
        #"{"trackID":"external-track","albumID":"external-album"}"#,
        #"{"v":1,"albumID":"third-party-id"}"#,
        #"{"v":1,"trackID":"external-track","albumID":"external-album"}"#,
        #"{"v":1,"trackID":"123"}"#,
        #"{"trackID":"123","albumID":"456""#,
    ])
    func `ordinary comments and unrelated JSON permit fallback`(_ comment: String) throws {
        #expect(try EmbeddedTrackIdentity.payload(from: comment) == nil)
    }

    @Test(arguments: [
        #"{"source":"MuseAmp","v":1,"trackID":"123"}"#,
        #"{"source":"MuseAmp","albumID":"456"}"#,
        #"{"source":"MuseAmp","trackID":"123""#,
        #"{"v":2,"trackID":"123","albumID":"456"}"#,
        #"{"v":true,"trackID":"123","albumID":"456"}"#,
        #"{"source":"MuseAmp","v":1,"trackID":123,"albumID":"456"}"#,
        #"{"source":"MuseAmp","trackID":"local-track-../escape","albumID":"456"}"#,
        #"{"source":"MuseAmp","v":1,"trackID":"123","albumID":"456""#,
    ])
    func `damaged or unsupported identity blocks fallback`(_ comment: String) {
        #expect(throws: EmbeddedTrackIdentity.IdentityError.self) {
            try EmbeddedTrackIdentity.payload(from: comment)
        }
    }

    @Test
    func `escaped JSON keys retain their embedded catalog IDs`() throws {
        let payload = try #require(try EmbeddedTrackIdentity.payload(from: #"{"\u0074rackID":"123","\u0061lbumID":"456"}"#))
        #expect(payload["trackID"] as? String == "123")
        #expect(payload["albumID"] as? String == "456")
    }

    @Test
    func `legacy catalog comments without version remain valid`() throws {
        let payload = try #require(try EmbeddedTrackIdentity.payload(from: #"{"trackID":"123","albumID":"456"}"#))
        #expect(payload["trackID"] as? String == "123")
        #expect(payload["albumID"] as? String == "456")
    }
}
