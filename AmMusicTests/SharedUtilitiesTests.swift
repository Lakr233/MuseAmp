@testable import AmMusic
import AVFoundation
import Testing
import UIKit

// MARK: - AVMetadataHelper Tests

@Suite(.serialized)
struct AVMetadataHelperTests {
    @Test("matches returns true when identifier contains token")
    func matchesIdentifier() throws {
        let item = AVMutableMetadataItem()
        item.identifier = .commonIdentifierArtwork
        let frozen = try #require(item.copy() as? AVMetadataItem)
        #expect(AVMetadataHelper.matches(frozen, tokens: ["artwork"]))
    }

    @Test("matches returns false for unrelated tokens")
    func matchesUnrelated() throws {
        let item = AVMutableMetadataItem()
        item.identifier = .commonIdentifierTitle
        let frozen = try #require(item.copy() as? AVMetadataItem)
        #expect(!AVMetadataHelper.matches(frozen, tokens: ["artwork", "coverart"]))
    }

    @Test("matches is case-insensitive")
    func matchesCaseInsensitive() throws {
        let item = AVMutableMetadataItem()
        item.identifier = .commonIdentifierArtwork
        let frozen = try #require(item.copy() as? AVMetadataItem)
        #expect(AVMetadataHelper.matches(frozen, tokens: ["ARTWORK"]) == false)
        #expect(AVMetadataHelper.matches(frozen, tokens: ["artwork"]))
    }

    @Test("matches with empty tokens returns false")
    func matchesEmptyTokens() throws {
        let item = AVMutableMetadataItem()
        item.identifier = .commonIdentifierTitle
        let frozen = try #require(item.copy() as? AVMetadataItem)
        #expect(!AVMetadataHelper.matches(frozen, tokens: []))
    }
}

// MARK: - sanitizedLogText Tests

@Suite(.serialized)
struct SanitizedLogTextTests {
    @Test("collapses whitespace")
    func collapsesWhitespace() {
        #expect(sanitizedLogText("hello   world") == "hello world")
    }

    @Test("trims leading and trailing whitespace")
    func trimsEdges() {
        #expect(sanitizedLogText("  hello  ") == "hello")
    }

    @Test("replaces double quotes with single quotes")
    func replacesQuotes() {
        #expect(sanitizedLogText("say \"hello\"") == "say 'hello'")
    }

    @Test("collapses newlines and tabs")
    func collapsesNewlines() {
        #expect(sanitizedLogText("line1\n\tline2") == "line1 line2")
    }

    @Test("truncates when maxLength is set")
    func truncates() {
        let result = sanitizedLogText("abcdefghij", maxLength: 5)
        #expect(result == "abcde...")
    }

    @Test("does not truncate when under maxLength")
    func noTruncateUnderLimit() {
        let result = sanitizedLogText("abc", maxLength: 10)
        #expect(result == "abc")
    }

    @Test("no truncation when maxLength is nil")
    func noTruncateNil() {
        let long = String(repeating: "a", count: 200)
        #expect(sanitizedLogText(long).count == 200)
    }

    @Test("handles empty string")
    func emptyString() {
        #expect(sanitizedLogText("") == "")
    }
}

// MARK: - UIView+RemoveAnimations Tests

@Suite(.serialized)
@MainActor
struct RemoveAnimationsTests {
    @Test("removeAnimationsRecursively visits subviews")
    func removesFromSubviews() {
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
    @Test("returns nil when identifier is not an IndexPath")
    func nilForInvalidIdentifier() {
        let tableView = UITableView()
        let config = UIContextMenuConfiguration(identifier: "bad" as NSString, previewProvider: nil, actionProvider: nil)
        let result = CellContextMenuPreviewHelper.targetedPreview(for: config, in: tableView)
        #expect(result == nil)
    }
}
