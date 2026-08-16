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

    @Test
    func `exact match does not confuse total track count with track number`() throws {
        let total = AVMutableMetadataItem()
        total.identifier = AVMetadataIdentifier(rawValue: "itlk/com.apple.iTunes.TRACKTOTAL")
        let frozenTotal = try #require(total.copy() as? AVMetadataItem)

        let track = AVMutableMetadataItem()
        track.identifier = AVMetadataIdentifier(rawValue: "itlk/com.apple.iTunes.TRACKNUMBER")
        let frozenTrack = try #require(track.copy() as? AVMetadataItem)

        #expect(!AVMetadataHelper.matchesExactly(frozenTotal, tokens: ["trackNumber", "track"]))
        #expect(AVMetadataHelper.matchesExactly(frozenTrack, tokens: ["trackNumber", "track"]))
    }

    @Test
    func `exact match recognizes format specific track keys`() throws {
        for identifier in ["itsk/trkn", "id3/TRCK"] {
            let item = AVMutableMetadataItem()
            item.identifier = AVMetadataIdentifier(rawValue: identifier)
            let frozen = try #require(item.copy() as? AVMetadataItem)
            #expect(AVMetadataHelper.matchesExactly(frozen, tokens: ["trkn", "trck"]))
        }
    }

    @Test
    func `integer value reads position from compound track value`() async throws {
        let track = AVMutableMetadataItem()
        track.identifier = AVMetadataIdentifier(rawValue: "itlk/com.apple.iTunes.TRACKNUMBER")
        track.value = "3/13" as NSString
        let frozenTrack = try #require(track.copy() as? AVMetadataItem)

        let value = await AVMetadataHelper.integerValue(
            in: [frozenTrack],
            matching: ["trackNumber", "track"],
        )
        #expect(value == 3)
    }

    @Test
    func `integer value skips iTunes total and reads binary track atom`() async throws {
        let total = AVMutableMetadataItem()
        total.identifier = AVMetadataIdentifier(rawValue: "itlk/com.apple.iTunes.TRACKTOTAL")
        total.value = 13 as NSNumber
        let frozenTotal = try #require(total.copy() as? AVMetadataItem)

        let track = AVMutableMetadataItem()
        track.identifier = AVMetadataIdentifier(rawValue: "itsk/trkn")
        track.value = Data([0, 0, 0, 3, 0, 13, 0, 0]) as NSData
        let frozenTrack = try #require(track.copy() as? AVMetadataItem)

        let value = await AVMetadataHelper.integerValue(
            in: [frozenTotal, frozenTrack],
            matching: ["trackNumber", "track", "trkn"],
        )
        #expect(value == 3)
    }

    @Test
    func `integer value skips iTunes disc total and reads binary disc atom`() async throws {
        let total = AVMutableMetadataItem()
        total.identifier = AVMetadataIdentifier(rawValue: "itlk/com.apple.iTunes.DISCTOTAL")
        total.value = 2 as NSNumber
        let frozenTotal = try #require(total.copy() as? AVMetadataItem)

        let disc = AVMutableMetadataItem()
        disc.identifier = AVMetadataIdentifier(rawValue: "itsk/disk")
        disc.value = Data([0, 0, 0, 1, 0, 2]) as NSData
        let frozenDisc = try #require(disc.copy() as? AVMetadataItem)

        let value = await AVMetadataHelper.integerValue(
            in: [frozenTotal, frozenDisc],
            matching: ["discNumber", "disc", "disk"],
        )
        #expect(value == 1)
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
