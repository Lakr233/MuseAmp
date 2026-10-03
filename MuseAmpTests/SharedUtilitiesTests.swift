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
