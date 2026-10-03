import AVFoundation
@testable import MuseAmp
import Testing
import UIKit

// MARK: - AVMetadataHelper Tests

@Suite(.serialized)
struct AVMetadataHelperTests {
    @Test
    func `matches returns true when identifier contains token`() throws {
        let item = AVMutableMetadataItem()
        item.identifier = .commonIdentifierArtwork
        let frozen = try #require(item.copy() as? AVMetadataItem)
        #expect(AVMetadataHelper.matches(frozen, tokens: ["artwork"]))
    }

    @Test
    func `matches returns false for unrelated tokens`() throws {
        let item = AVMutableMetadataItem()
        item.identifier = .commonIdentifierTitle
        let frozen = try #require(item.copy() as? AVMetadataItem)
        #expect(!AVMetadataHelper.matches(frozen, tokens: ["artwork", "coverart"]))
    }

    @Test
    func `matches is case-insensitive`() throws {
        let item = AVMutableMetadataItem()
        item.identifier = .commonIdentifierArtwork
        let frozen = try #require(item.copy() as? AVMetadataItem)
        #expect(AVMetadataHelper.matches(frozen, tokens: ["ARTWORK"]) == false)
        #expect(AVMetadataHelper.matches(frozen, tokens: ["artwork"]))
    }

    @Test
    func `matches with empty tokens returns false`() throws {
        let item = AVMutableMetadataItem()
        item.identifier = .commonIdentifierTitle
        let frozen = try #require(item.copy() as? AVMetadataItem)
        #expect(!AVMetadataHelper.matches(frozen, tokens: []))
    }
}

// MARK: - Album Artist Tag Tests

/// Items are built the way AVFoundation exposes them when it reads a file:
/// by key space and key, with the identifier derived from those.
@Suite(.serialized)
struct AVMetadataHelperAlbumArtistTests {
    /// iTunes atom keys come back as their four-character code in an NSNumber.
    private func fourCharacterCode(_ code: String) -> NSNumber {
        NSNumber(value: Int32(bitPattern: code.unicodeScalars.reduce(UInt32(0)) { ($0 << 8) | $1.value }))
    }

    private func item(
        keySpace: AVMetadataKeySpace,
        key: NSObjectProtocol & NSCopying,
        value: String,
    ) throws -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.keySpace = keySpace
        item.key = key
        item.value = value as NSString
        item.dataType = kCMMetadataBaseDataType_UTF8 as String
        return try #require(item.copy() as? AVMetadataItem)
    }

    @Test
    func `reads the M4A aART atom`() async throws {
        let albumArtist = try item(keySpace: .iTunes, key: fourCharacterCode("aART"), value: "Artist A")
        #expect(albumArtist.identifier == .iTunesMetadataAlbumArtist)
        // The substring matcher used for other tags never finds it.
        #expect(!AVMetadataHelper.matches(albumArtist, tokens: ["albumartist"]))

        let items = try [
            item(keySpace: .iTunes, key: fourCharacterCode("\u{A9}ART"), value: "Artist A, Artist B"),
            albumArtist,
        ]
        #expect(await AVMetadataHelper.albumArtistName(in: items) == "Artist A")
    }

    @Test
    func `reads the ID3 TPE2 frame`() async throws {
        let items = try [
            item(keySpace: .id3, key: "TPE1" as NSString, value: "Track Artist"),
            item(keySpace: .id3, key: "TPE2" as NSString, value: "Album Artist"),
        ]
        #expect(await AVMetadataHelper.albumArtistName(in: items) == "Album Artist")
    }

    @Test
    func `reads free-form album artist keys by their whole name`() async throws {
        let quickTime = try item(keySpace: .quickTimeMetadata, key: "album_artist" as NSString, value: "QuickTime Artist")
        // iTunes `----` atoms come back in the `itlk` key space, which has no
        // named constant.
        let iTunesFreeForm = try item(
            keySpace: AVMetadataKeySpace(rawValue: "itlk"),
            key: "com.apple.iTunes.ALBUMARTIST" as NSString,
            value: "Free-form Artist",
        )
        #expect(await AVMetadataHelper.albumArtistName(in: [quickTime]) == "QuickTime Artist")
        #expect(await AVMetadataHelper.albumArtistName(in: [iTunesFreeForm]) == "Free-form Artist")
    }

    @Test
    func `prefers aART over other album artist tags`() async throws {
        let items = try [
            item(keySpace: .quickTimeMetadata, key: "album_artist" as NSString, value: "Other"),
            item(keySpace: .id3, key: "TPE2" as NSString, value: "Band"),
            item(keySpace: .iTunes, key: fourCharacterCode("aART"), value: "Preferred"),
        ]
        #expect(await AVMetadataHelper.albumArtistName(in: items) == "Preferred")
    }

    @Test
    func `ignores track artist and keys that only contain artist`() async throws {
        let items = try [
            item(keySpace: .iTunes, key: fourCharacterCode("\u{A9}ART"), value: "Track Artist"),
            item(keySpace: .quickTimeMetadata, key: "com.apple.quicktime.artist" as NSString, value: "Track Artist"),
            item(keySpace: .quickTimeMetadata, key: "original_album_artist_sort" as NSString, value: "Sort"),
            item(keySpace: .iTunes, key: fourCharacterCode("aART"), value: "   "),
        ]
        #expect(await AVMetadataHelper.albumArtistName(in: items) == nil)
    }
}

// MARK: - Track and Disc Number Tests

/// Items are built the way AVFoundation exposes them when it reads a file:
/// iTunes atoms by key space and numeric key with a raw data value, free-form
/// atoms by their full key name.
@Suite(.serialized)
struct AVMetadataHelperTrackNumberTests {
    private func fourCharacterCode(_ code: String) -> NSNumber {
        NSNumber(value: Int32(bitPattern: code.unicodeScalars.reduce(UInt32(0)) { ($0 << 8) | $1.value }))
    }

    private func atom(_ code: String, bytes: [UInt8]) throws -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.keySpace = .iTunes
        item.key = fourCharacterCode(code)
        item.value = Data(bytes) as NSData
        item.dataType = kCMMetadataBaseDataType_RawData as String
        return try #require(item.copy() as? AVMetadataItem)
    }

    private func text(keySpace: AVMetadataKeySpace, key: String, value: String) throws -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.keySpace = keySpace
        item.key = key as NSString
        item.value = value as NSString
        item.dataType = kCMMetadataBaseDataType_UTF8 as String
        return try #require(item.copy() as? AVMetadataItem)
    }

    private var iTunesFreeForm: AVMetadataKeySpace {
        AVMetadataKeySpace(rawValue: "itlk")
    }

    @Test
    func `reads the position from binary trkn and disk atoms`() async throws {
        let trkn = try atom("trkn", bytes: [0, 0, 0, 3, 0, 13, 0, 0])
        let disk = try atom("disk", bytes: [0, 0, 0, 1, 0, 1])
        #expect(trkn.identifier == .iTunesMetadataTrackNumber)
        #expect(disk.identifier == .iTunesMetadataDiscNumber)
        // The substring matcher never finds the numeric keys.
        #expect(!AVMetadataHelper.matches(trkn, tokens: ["tracknumber", "track"]))

        #expect(await AVMetadataHelper.trackNumber(in: [trkn]) == 3)
        #expect(await AVMetadataHelper.discNumber(in: [disk]) == 1)
    }

    @Test
    func `reads positions above 255 as big-endian`() async throws {
        let trkn = try atom("trkn", bytes: [0, 0, 0x01, 0x2C, 0x01, 0x2C, 0, 0])
        #expect(await AVMetadataHelper.trackNumber(in: [trkn]) == 300)
    }

    @Test
    func `TRACKTOTAL and DISCTOTAL before the atoms are never the position`() async throws {
        let items = try [
            text(keySpace: iTunesFreeForm, key: "com.apple.iTunes.TRACKTOTAL", value: "13"),
            text(keySpace: iTunesFreeForm, key: "com.apple.iTunes.DISCTOTAL", value: "2"),
            atom("trkn", bytes: [0, 0, 0, 3, 0, 13, 0, 0]),
            atom("disk", bytes: [0, 0, 0, 1, 0, 2]),
        ]
        #expect(await AVMetadataHelper.trackNumber(in: items) == 3)
        #expect(await AVMetadataHelper.discNumber(in: items) == 1)

        let totalsOnly = Array(items.prefix(2))
        #expect(await AVMetadataHelper.trackNumber(in: totalsOnly) == nil)
        #expect(await AVMetadataHelper.discNumber(in: totalsOnly) == nil)
    }

    @Test
    func `reads the position from text such as 3 of 13`() async throws {
        let freeForm = try [
            text(keySpace: iTunesFreeForm, key: "com.apple.iTunes.TRACKNUMBER", value: "3/13"),
            text(keySpace: iTunesFreeForm, key: "com.apple.iTunes.DISCNUMBER", value: "1/1"),
        ]
        #expect(await AVMetadataHelper.trackNumber(in: freeForm) == 3)
        #expect(await AVMetadataHelper.discNumber(in: freeForm) == 1)

        let id3 = try [
            text(keySpace: .id3, key: "TRCK", value: "07/12"),
            text(keySpace: .id3, key: "TPOS", value: "2/2"),
        ]
        #expect(await AVMetadataHelper.trackNumber(in: id3) == 7)
        #expect(await AVMetadataHelper.discNumber(in: id3) == 2)

        let quickTime = try [text(keySpace: .quickTimeMetadata, key: "track", value: "5")]
        #expect(await AVMetadataHelper.trackNumber(in: quickTime) == 5)
    }

    @Test
    func `prefers the trkn atom and skips empty positions`() async throws {
        let items = try [
            text(keySpace: iTunesFreeForm, key: "com.apple.iTunes.TRACKNUMBER", value: "9"),
            atom("trkn", bytes: [0, 0, 0, 4, 0, 0, 0, 0]),
        ]
        #expect(await AVMetadataHelper.trackNumber(in: items) == 4)

        let emptyAtom = try [
            atom("trkn", bytes: [0, 0, 0, 0, 0, 12, 0, 0]),
            text(keySpace: .id3, key: "TRCK", value: "6"),
        ]
        #expect(await AVMetadataHelper.trackNumber(in: emptyAtom) == 6)
    }
}

// MARK: - sanitizedLogText Tests

@Suite(.serialized)
struct SanitizedLogTextTests {
    @Test
    func `collapses whitespace`() {
        #expect(sanitizedLogText("hello   world") == "hello world")
    }

    @Test
    func `trims leading and trailing whitespace`() {
        #expect(sanitizedLogText("  hello  ") == "hello")
    }

    @Test
    func `replaces double quotes with single quotes`() {
        #expect(sanitizedLogText("say \"hello\"") == "say 'hello'")
    }

    @Test
    func `collapses newlines and tabs`() {
        #expect(sanitizedLogText("line1\n\tline2") == "line1 line2")
    }

    @Test
    func `truncates when maxLength is set`() {
        let result = sanitizedLogText("abcdefghij", maxLength: 5)
        #expect(result == "abcde...")
    }

    @Test
    func `does not truncate when under maxLength`() {
        let result = sanitizedLogText("abc", maxLength: 10)
        #expect(result == "abc")
    }

    @Test
    func `no truncation when maxLength is nil`() {
        let long = String(repeating: "a", count: 200)
        #expect(sanitizedLogText(long).count == 200)
    }

    @Test
    func `handles empty string`() {
        #expect(sanitizedLogText("") == "")
    }
}

// MARK: - UIView+RemoveAnimations Tests

@Suite(.serialized)
@MainActor
struct RemoveAnimationsTests {
    @Test
    func `removeAnimationsRecursively visits subviews`() {
        let parent = UIView()
        let child = UIView()
        let grandchild = UIView()
        parent.addSubview(child)
        child.addSubview(grandchild)

        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 0
        animation.toValue = 1
        animation.duration = 1
        grandchild.layer.add(animation, forKey: "test")

        #expect(grandchild.layer.animationKeys()?.isEmpty == false)
        parent.removeAnimationsRecursively()
        #expect(grandchild.layer.animationKeys() == nil)
    }
}

// MARK: - CellContextMenuPreviewHelper Tests

@Suite(.serialized)
@MainActor
struct CellContextMenuPreviewHelperTests {
    @Test
    func `returns nil when identifier is not an IndexPath`() {
        let tableView = UITableView()
        let config = UIContextMenuConfiguration(identifier: "bad" as NSString, previewProvider: nil, actionProvider: nil)
        let result = CellContextMenuPreviewHelper.targetedPreview(for: config, in: tableView)
        #expect(result == nil)
    }
}
