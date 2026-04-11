@testable import AmMusic
import AVFoundation
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
