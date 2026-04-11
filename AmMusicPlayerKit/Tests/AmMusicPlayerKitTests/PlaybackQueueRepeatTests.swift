//
//  PlaybackQueueRepeatTests.swift
//  AmMusicPlayerKit
//
//  Created by @Lakr233 on 2026/04/11.
//

@testable import AmMusicPlayerKit
import Foundation
import Testing

struct PlaybackQueueRepeatTests {
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

    @Test func `repeat queue recycles to start when exhausted`() {
        var queue = PlaybackQueue()
        let items = Self.makeItems(3)
        queue.load(items: items, startIndex: 0, shuffle: false)
        queue.setRepeatMode(.queue)

        _ = queue.advance() // items[1]
        _ = queue.advance() // items[2]
        let recycled = queue.advance() // should recycle to items[0]

        #expect(recycled == items[0])
        #expect(queue.history.isEmpty) // history cleared on recycle
    }

    @Test func `repeat off stops at end`() {
        var queue = PlaybackQueue()
        let items = Self.makeItems(2)
        queue.load(items: items, startIndex: 0, shuffle: false)
        queue.setRepeatMode(.off)

        _ = queue.advance() // items[1]
        let result = queue.advance()

        #expect(result == nil)
    }

    @Test func `repeat queue can play through multiple cycles`() {
        var queue = PlaybackQueue()
        let items = Self.makeItems(2)
        queue.load(items: items, startIndex: 0, shuffle: false)
        queue.setRepeatMode(.queue)

        // First cycle
        _ = queue.advance() // items[1]
        _ = queue.advance() // recycle to items[0]

        // Second cycle
        let second = queue.advance()
        #expect(second == items[1])
    }

    @Test func `repeat queue with shuffle reshuffles on recycle`() {
        var queue = PlaybackQueue()
        let items = Self.makeItems(10)
        queue.load(items: items, startIndex: 0, shuffle: true)
        queue.setRepeatMode(.queue)

        // Play through all items
        for _ in 0 ..< 9 {
            _ = queue.advance()
        }

        // Recycle
        let recycled = queue.advance()
        #expect(recycled != nil)
        #expect(queue.history.isEmpty)
    }

    @Test func `set repeat mode changes mode`() {
        var queue = PlaybackQueue()
        queue.load(items: Self.makeItems(2), startIndex: 0, shuffle: false)

        queue.setRepeatMode(.track)
        #expect(queue.repeatMode == .track)

        queue.setRepeatMode(.queue)
        #expect(queue.repeatMode == .queue)

        queue.setRepeatMode(.off)
        #expect(queue.repeatMode == .off)
    }
}
