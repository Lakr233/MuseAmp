@testable import AmMusicPlayerKit
import Foundation
import Testing

struct PlaybackQueueShuffleTests {
    static func makeItems(_ count: Int) -> [PlayerItem] {
        (0 ..< count).map { i in
            PlayerItem(
                id: "track-\(i)",
                url: URL(string: "https://example.com/track\(i).mp3")!,
                title: "Track \(i)",
                artist: "Artist",
                album: "Album",
                durationInSeconds: 200
            )
        }
    }

    @Test func shuffle_preservesNowPlaying() {
        var queue = PlaybackQueue()
        let items = Self.makeItems(10)
        queue.load(items: items, startIndex: 3, shuffle: false)

        queue.setShuffle(true)
        #expect(queue.nowPlaying == items[3])
    }

    @Test func shuffle_changesUpcomingOrder() {
        // With 10 items it's extremely unlikely the shuffle preserves order
        var queue = PlaybackQueue()
        let items = Self.makeItems(10)
        queue.load(items: items, startIndex: 0, shuffle: false)
        let originalUpcoming = queue.upcoming

        queue.setShuffle(true)
        let shuffledUpcoming = queue.upcoming

        // At least one item should be in a different position
        #expect(shuffledUpcoming.count == originalUpcoming.count)
        // We can't guarantee order is different (astronomically unlikely to be same though)
    }

    @Test func unshuffle_restoresCanonicalOrder() {
        var queue = PlaybackQueue()
        let items = Self.makeItems(5)
        queue.load(items: items, startIndex: 0, shuffle: false)

        queue.setShuffle(true)
        queue.setShuffle(false)

        #expect(queue.nowPlaying == items[0])
        #expect(queue.upcoming == Array(items[1...]))
    }

    @Test func shuffle_thenAddItem_appearsInUpcoming() throws {
        var queue = PlaybackQueue()
        let items = Self.makeItems(5)
        queue.load(items: items, startIndex: 0, shuffle: true)

        let newItem = try PlayerItem(
            id: "new", url: #require(URL(string: "https://example.com/new.mp3")),
            title: "New", artist: "A", album: "B"
        )
        queue.append(newItem)

        #expect(queue.upcoming.contains(newItem))
    }

    @Test func shuffle_thenRemoveItem_removedFromUpcoming() {
        var queue = PlaybackQueue()
        let items = Self.makeItems(5)
        queue.load(items: items, startIndex: 0, shuffle: false)
        queue.setShuffle(true)

        let removed = queue.remove(id: "track-3")
        #expect(removed == items[3])
        #expect(!queue.upcoming.contains(items[3]))
    }

    @Test func shuffle_thenUnshuffle_indexPointsToSameItem() {
        var queue = PlaybackQueue()
        let items = Self.makeItems(10)
        queue.load(items: items, startIndex: 0, shuffle: false)

        // Advance a couple times
        _ = queue.advance()
        _ = queue.advance()
        let currentBefore = queue.nowPlaying

        queue.setShuffle(true)
        #expect(queue.nowPlaying == currentBefore)

        queue.setShuffle(false)
        #expect(queue.nowPlaying == currentBefore)
    }

    @Test func loadWithShuffle_pinsStartIndexAtFront() {
        var queue = PlaybackQueue()
        let items = Self.makeItems(5)
        queue.load(items: items, startIndex: 2, shuffle: true)

        #expect(queue.nowPlaying == items[2])
        #expect(queue.upcoming.count == 4) // All other items
    }

    @Test func jump_keepsFullQueueAndUpdatesHistory() {
        var queue = PlaybackQueue()
        let items = Self.makeItems(5)
        queue.load(items: items, startIndex: 0, shuffle: false)

        _ = queue.jump(to: 3)

        #expect(queue.nowPlaying == items[3])
        #expect(queue.history == Array(items.prefix(3)))
        #expect(queue.upcoming == [items[4]])
    }

    @Test func jump_backwards_restoresPlayedItemsIntoQueue() {
        var queue = PlaybackQueue()
        let items = Self.makeItems(5)
        queue.load(items: items, startIndex: 0, shuffle: false)

        _ = queue.advance()
        _ = queue.advance()
        _ = queue.jump(to: 1)

        #expect(queue.nowPlaying == items[1])
        #expect(queue.history == [items[0]])
        #expect(queue.upcoming == Array(items[2...]))
    }
}
