//
//  PlaybackQueueTests.swift
//  AmMusicPlayerKit
//
//  Created by @Lakr233 on 2026/04/11.
//

@testable import AmMusicPlayerKit
import Foundation
import Testing

struct PlaybackQueueTests {
    static func makeItems(_ count: Int) -> [PlayerItem] {
        (0 ..< count).map { i in
            PlayerItem(
                id: "track-\(i)",
                url: URL(string: "https://example.com/track\(i).mp3")!,
                title: "Track \(i)",
                artist: "Artist",
                album: "Album",
                durationInSeconds: 200,
            )
        }
    }

    @Test func `load sets now playing to start index`() {
        var queue = PlaybackQueue()
        let items = Self.makeItems(5)
        queue.load(items: items, startIndex: 2, shuffle: false)

        #expect(queue.nowPlaying == items[2])
        #expect(queue.history.isEmpty)
        #expect(queue.upcoming.count == 2) // items[3], items[4]
    }

    @Test func `load with empty items clears`() {
        var queue = PlaybackQueue()
        queue.load(items: Self.makeItems(3), startIndex: 0, shuffle: false)
        queue.load(items: [], startIndex: 0, shuffle: false)

        #expect(queue.nowPlaying == nil)
        #expect(queue.items.isEmpty)
    }

    @Test func `advance moves to next item`() {
        var queue = PlaybackQueue()
        let items = Self.makeItems(3)
        queue.load(items: items, startIndex: 0, shuffle: false)

        let next = queue.advance()
        #expect(next == items[1])
        #expect(queue.nowPlaying == items[1])
        #expect(queue.history == [items[0]])
    }

    @Test func `advance when exhausted and repeat off returns nil`() {
        var queue = PlaybackQueue()
        let items = Self.makeItems(2)
        queue.load(items: items, startIndex: 0, shuffle: false)

        _ = queue.advance() // items[1]
        let result = queue.advance() // exhausted
        #expect(result == nil)
    }

    @Test func `advance when exhausted and repeat queue recycles to start`() {
        var queue = PlaybackQueue()
        let items = Self.makeItems(2)
        queue.load(items: items, startIndex: 0, shuffle: false)
        queue.setRepeatMode(.queue)

        _ = queue.advance() // items[1]
        let result = queue.advance() // recycle
        #expect(result == items[0])
        #expect(queue.history.isEmpty)
    }

    @Test func `rewind when over3 seconds restarts`() {
        var queue = PlaybackQueue()
        queue.load(items: Self.makeItems(3), startIndex: 1, shuffle: false)

        let result = queue.rewind(currentTime: 5.0)
        if case .restart = result {
            // expected
        } else {
            Issue.record("Expected .restart, got \(result)")
        }
    }

    @Test func `rewind when under3 seconds goes to previous`() {
        var queue = PlaybackQueue()
        let items = Self.makeItems(3)
        queue.load(items: items, startIndex: 0, shuffle: false)
        _ = queue.advance() // now at items[1], history = [items[0]]

        let result = queue.rewind(currentTime: 1.0)
        if case let .previous(item) = result {
            #expect(item == items[0])
        } else {
            Issue.record("Expected .previous, got \(result)")
        }
    }

    @Test func `rewind when no history restarts`() {
        var queue = PlaybackQueue()
        queue.load(items: Self.makeItems(3), startIndex: 0, shuffle: false)

        let result = queue.rewind(currentTime: 1.0)
        if case .restart = result {
            // expected
        } else {
            Issue.record("Expected .restart, got \(result)")
        }
    }

    @Test func `skip to upcoming index works`() {
        var queue = PlaybackQueue()
        let items = Self.makeItems(5)
        queue.load(items: items, startIndex: 0, shuffle: false)

        let result = queue.skip(to: 2) // skip to upcoming[2] = items[3]
        #expect(result == items[3])
        #expect(queue.nowPlaying == items[3])
    }

    @Test func `play next inserts at upcoming zero`() throws {
        var queue = PlaybackQueue()
        let items = Self.makeItems(3)
        queue.load(items: items, startIndex: 0, shuffle: false)

        let newItem = try PlayerItem(
            id: "new", url: #require(URL(string: "https://example.com/new.mp3")),
            title: "New", artist: "A", album: "B",
        )
        queue.playNext(newItem)

        #expect(queue.upcoming.first == newItem)
    }

    @Test func `append adds to end`() throws {
        var queue = PlaybackQueue()
        let items = Self.makeItems(2)
        queue.load(items: items, startIndex: 0, shuffle: false)

        let newItem = try PlayerItem(
            id: "new", url: #require(URL(string: "https://example.com/new.mp3")),
            title: "New", artist: "A", album: "B",
        )
        queue.append(newItem)

        #expect(queue.upcoming.last == newItem)
    }

    @Test func `remove at index returns item`() {
        var queue = PlaybackQueue()
        let items = Self.makeItems(4)
        queue.load(items: items, startIndex: 0, shuffle: false)

        let removed = queue.remove(at: 0) // remove upcoming[0] = items[1]
        #expect(removed == items[1])
        #expect(queue.upcoming.count == 2) // items[2], items[3]
    }

    @Test func `remove by ID works`() {
        var queue = PlaybackQueue()
        let items = Self.makeItems(4)
        queue.load(items: items, startIndex: 0, shuffle: false)

        let removed = queue.remove(id: "track-2")
        #expect(removed == items[2])
    }

    @Test func `remove by ID does not remove current`() {
        var queue = PlaybackQueue()
        let items = Self.makeItems(3)
        queue.load(items: items, startIndex: 0, shuffle: false)

        let removed = queue.remove(id: "track-0")
        #expect(removed == nil) // can't remove currently playing
    }

    @Test func `move reorders upcoming`() {
        var queue = PlaybackQueue()
        let items = Self.makeItems(5)
        queue.load(items: items, startIndex: 0, shuffle: false)

        // upcoming is [1,2,3,4], move index 0 to index 2
        queue.move(from: 0, to: 2)
        let upcoming = queue.upcoming
        #expect(upcoming[0] == items[2])
        #expect(upcoming[1] == items[3])
        #expect(upcoming[2] == items[1])
    }

    @Test func `clear upcoming empties only upcoming`() {
        var queue = PlaybackQueue()
        let items = Self.makeItems(4)
        queue.load(items: items, startIndex: 1, shuffle: false)
        _ = queue.advance()

        // history should have items[1], current = items[2]
        queue.clearUpcoming()
        #expect(queue.upcoming.isEmpty)
        #expect(queue.nowPlaying != nil)
    }

    @Test func `replace all resets everything`() {
        var queue = PlaybackQueue()
        queue.load(items: Self.makeItems(3), startIndex: 0, shuffle: false)
        _ = queue.advance()

        let newItems = Self.makeItems(2)
        queue.replaceAll(items: newItems, startIndex: 0)

        #expect(queue.nowPlaying == newItems[0])
        #expect(queue.history.isEmpty)
        #expect(queue.upcoming.count == 1)
    }

    @Test func `snapshot reflects current state`() {
        var queue = PlaybackQueue()
        let items = Self.makeItems(4)
        queue.load(items: items, startIndex: 0, shuffle: false)
        _ = queue.advance()

        let snap = queue.snapshot()
        #expect(snap.history == [items[0]])
        #expect(snap.nowPlaying == items[1])
        #expect(snap.upcoming == [items[2], items[3]])
        #expect(snap.shuffled == false)
        #expect(snap.repeatMode == .off)
        #expect(snap.totalCount == 4)
    }
}
