//
//  PlaybackQueue.swift
//  AmMusicPlayerKit
//
//  Created by @Lakr233 on 2026/04/11.
//

import Foundation

enum RewindResult {
    case restart
    case previous(PlayerItem)
}

struct PlaybackQueue {
    // MARK: - Authoritative State

    /// Canonical insertion-order list of all items in the queue.
    private(set) var items: [PlayerItem] = []

    /// Index into `effectiveOrder` pointing at the currently playing item.
    /// `nil` means nothing is playing.
    private(set) var currentIndex: Int?

    /// Canonical indices that have already been played, in play order (for history).
    private(set) var playedIndices: [Int] = []

    /// When shuffled, a permutation of canonical indices defining play order.
    var shufflePermutation: [Int] = []

    private(set) var shuffled: Bool = false
    private(set) var repeatMode: RepeatMode = .off

    // MARK: - Derived

    /// The current play order as indices into `items`.
    var effectiveOrder: [Int] {
        shuffled ? shufflePermutation : Array(0 ..< items.count)
    }

    /// The currently playing item.
    var nowPlaying: PlayerItem? {
        guard let ci = currentIndex else { return nil }
        let order = effectiveOrder
        guard ci >= 0, ci < order.count else { return nil }
        return items[order[ci]]
    }

    /// Items that have already been played, in play order.
    var history: [PlayerItem] {
        playedIndices.map { items[$0] }
    }

    /// Items coming up after the current one, in play order.
    var upcoming: [PlayerItem] {
        guard let ci = currentIndex else { return [] }
        let order = effectiveOrder
        guard ci + 1 < order.count else { return [] }
        return order[(ci + 1)...].map { items[$0] }
    }

    // MARK: - Load / Clear

    mutating func load(items: [PlayerItem], startIndex: Int, shuffle: Bool) {
        guard !items.isEmpty else {
            clear()
            return
        }

        self.items = items
        playedIndices = []

        let clampedStart = min(max(startIndex, 0), items.count - 1)

        if shuffle {
            shuffled = true
            generateShufflePermutation(pinningCurrent: clampedStart)
            currentIndex = 0 // pinned item is at position 0
        } else {
            shuffled = false
            shufflePermutation = []
            currentIndex = clampedStart
        }
    }

    mutating func restore(
        items: [PlayerItem],
        currentIndex: Int,
        shuffled: Bool,
        repeatMode: RepeatMode,
    ) {
        guard !items.isEmpty else {
            clear()
            self.repeatMode = repeatMode
            return
        }

        self.items = items
        self.repeatMode = repeatMode
        let clampedCurrentIndex = min(max(currentIndex, 0), items.count - 1)
        playedIndices = clampedCurrentIndex > 0 ? Array(0 ..< clampedCurrentIndex) : []
        self.shuffled = shuffled
        shufflePermutation = shuffled ? Array(0 ..< items.count) : []
        self.currentIndex = clampedCurrentIndex
    }

    mutating func clear() {
        items = []
        currentIndex = nil
        playedIndices = []
        shufflePermutation = []
        shuffled = false
    }

    // MARK: - Navigation

    mutating func advance() -> PlayerItem? {
        guard let ci = currentIndex else { return nil }

        let order = effectiveOrder

        // Mark current as played
        if ci < order.count {
            playedIndices.append(order[ci])
        }

        let nextIndex = ci + 1

        if nextIndex < order.count {
            currentIndex = nextIndex
            return nowPlaying
        }

        // Queue exhausted
        if repeatMode == .queue {
            playedIndices = []
            if shuffled {
                generateShufflePermutation(pinningCurrent: nil)
            }
            currentIndex = 0
            return nowPlaying
        }

        // No repeat — end of queue
        currentIndex = nil
        return nil
    }

    mutating func rewind(currentTime: TimeInterval) -> RewindResult {
        guard currentIndex != nil else { return .restart }

        if currentTime > 3.0 {
            return .restart
        }

        let order = effectiveOrder
        guard let lastPlayed = playedIndices.popLast() else {
            guard repeatMode == .queue,
                  let targetPosition = order.indices.last
            else {
                return .restart
            }

            playedIndices = targetPosition > 0 ? Array(order.prefix(targetPosition)) : []
            currentIndex = targetPosition
            return .previous(items[order[targetPosition]])
        }

        // Move current back to upcoming by decrementing currentIndex
        if let ci = currentIndex, ci < order.count {
            // Find position of lastPlayed in effectiveOrder
            if let targetPos = order.firstIndex(of: lastPlayed) {
                currentIndex = targetPos
                return .previous(items[lastPlayed])
            }
        }

        // Fallback: insert at current position
        if shuffled {
            if let ci = currentIndex {
                shufflePermutation.insert(lastPlayed, at: ci)
                // currentIndex stays the same, now pointing at the restored item
            }
        }
        currentIndex = currentIndex ?? 0
        return .previous(items[lastPlayed])
    }

    mutating func skip(to upcomingIndex: Int) -> PlayerItem? {
        guard let ci = currentIndex else { return nil }

        let actualIndex = ci + 1 + upcomingIndex
        let order = effectiveOrder
        guard actualIndex >= 0, actualIndex < order.count else { return nil }

        // Mark current and skipped items as played
        for i in ci ..< actualIndex {
            if i < order.count {
                playedIndices.append(order[i])
            }
        }

        currentIndex = actualIndex
        return nowPlaying
    }

    mutating func jump(to queueIndex: Int) -> PlayerItem? {
        let order = effectiveOrder
        guard currentIndex != nil,
              order.indices.contains(queueIndex)
        else {
            return nil
        }

        playedIndices = queueIndex > 0 ? Array(order.prefix(queueIndex)) : []
        currentIndex = queueIndex
        return nowPlaying
    }

    // MARK: - Queue Editing (indices refer to upcoming view)

    mutating func playNext(_ item: PlayerItem) {
        insert(item, at: 0)
    }

    mutating func playNext(_ items: [PlayerItem]) {
        for (offset, item) in items.enumerated() {
            insert(item, at: offset)
        }
    }

    mutating func append(_ item: PlayerItem) {
        let canonicalIndex = items.count
        items.append(item)
        if shuffled {
            shufflePermutation.append(canonicalIndex)
        }
    }

    mutating func append(_ items: [PlayerItem]) {
        for item in items {
            append(item)
        }
    }

    mutating func insert(_ item: PlayerItem, at upcomingIndex: Int) {
        let canonicalIndex = items.count
        items.append(item)

        if shuffled {
            let insertPos = insertionPosition(forUpcomingIndex: upcomingIndex)
            shufflePermutation.insert(canonicalIndex, at: insertPos)
        }
        // When not shuffled, appending to items already puts it at the right
        // canonical position — but we need to insert at the right spot.
        // Since canonical order = effective order when not shuffled,
        // we need to move the item from the end to the right position.
        if !shuffled {
            let targetCanonical = (currentIndex ?? -1) + 1 + upcomingIndex
            let clampedTarget = min(max(targetCanonical, 0), items.count - 1)
            if clampedTarget != canonicalIndex {
                let removed = items.removeLast()
                items.insert(removed, at: clampedTarget)
                // Adjust playedIndices for shifted canonical indices
                adjustPlayedIndicesAfterInsert(at: clampedTarget)
                // Adjust currentIndex if needed
                if let ci = currentIndex, clampedTarget <= ci {
                    currentIndex = ci + 1
                }
            }
        }
    }

    @discardableResult
    mutating func remove(at upcomingIndex: Int) -> PlayerItem? {
        guard let ci = currentIndex else { return nil }

        let order = effectiveOrder
        let effectiveIndex = ci + 1 + upcomingIndex
        guard effectiveIndex >= 0, effectiveIndex < order.count else { return nil }

        let canonicalIndex = order[effectiveIndex]
        let item = items[canonicalIndex]

        removeCanonicalIndex(canonicalIndex)
        return item
    }

    @discardableResult
    mutating func remove(id: String) -> PlayerItem? {
        guard let canonicalIndex = items.firstIndex(where: { $0.id == id }) else { return nil }

        // Don't remove the currently playing item via this method
        if let ci = currentIndex {
            let order = effectiveOrder
            if ci < order.count, order[ci] == canonicalIndex {
                return nil
            }
        }

        let item = items[canonicalIndex]
        removeCanonicalIndex(canonicalIndex)
        return item
    }

    mutating func move(from sourceUpcoming: Int, to destUpcoming: Int) {
        guard let ci = currentIndex else { return }
        guard sourceUpcoming != destUpcoming else { return }

        if shuffled {
            let sourceEffective = ci + 1 + sourceUpcoming
            let destEffective = ci + 1 + destUpcoming
            guard sourceEffective < shufflePermutation.count,
                  destEffective < shufflePermutation.count else { return }

            let val = shufflePermutation.remove(at: sourceEffective)
            shufflePermutation.insert(val, at: destEffective)
        } else {
            let sourceCanonical = ci + 1 + sourceUpcoming
            let destCanonical = ci + 1 + destUpcoming
            guard sourceCanonical < items.count, destCanonical < items.count else { return }

            let item = items.remove(at: sourceCanonical)
            items.insert(item, at: destCanonical)
            rebuildPlayedIndicesAfterReorder(from: sourceCanonical, to: destCanonical)
        }
    }

    mutating func clearUpcoming() {
        guard let ci = currentIndex else { return }

        if shuffled {
            // Identify canonical indices to keep: played + current
            let keptPermutation = Array(shufflePermutation.prefix(ci + 1))
            let keptCanonical = Set(keptPermutation + playedIndices)

            // Build mapping from old canonical index to new
            var indexMap: [Int: Int] = [:]
            var newItems: [PlayerItem] = []
            for (oldIdx, item) in items.enumerated() {
                if keptCanonical.contains(oldIdx) {
                    indexMap[oldIdx] = newItems.count
                    newItems.append(item)
                }
            }

            items = newItems
            shufflePermutation = keptPermutation.compactMap { indexMap[$0] }
            playedIndices = playedIndices.compactMap { indexMap[$0] }
            // currentIndex stays the same position in the permutation
        } else {
            let keepCount = ci + 1
            if keepCount < items.count {
                items.removeSubrange(keepCount...)
            }
        }
    }

    mutating func replaceAll(items: [PlayerItem], startIndex: Int) {
        self.items = items
        playedIndices = []
        if items.isEmpty {
            currentIndex = nil
            shufflePermutation = []
            return
        }
        let clamped = min(max(startIndex, 0), items.count - 1)
        if shuffled {
            generateShufflePermutation(pinningCurrent: clamped)
            currentIndex = 0
        } else {
            shufflePermutation = []
            currentIndex = clamped
        }
    }

    // MARK: - Modes

    mutating func setShuffle(_ enabled: Bool) {
        guard enabled != shuffled else { return }

        if enabled {
            let currentCanonical: Int? = if let ci = currentIndex, ci < items.count {
                ci // In non-shuffled mode, effectiveOrder index == canonical index
            } else {
                nil
            }
            shuffled = true
            generateShufflePermutation(pinningCurrent: currentCanonical)
            // The pinned item is placed right after playedIndices in the permutation
            currentIndex = currentCanonical != nil ? playedIndices.count : nil
        } else {
            // Read current canonical index from the shuffle permutation BEFORE clearing
            guard let ci = currentIndex, ci < shufflePermutation.count else {
                shuffled = false
                shufflePermutation = []
                currentIndex = nil
                return
            }
            let currentCanonical = shufflePermutation[ci]
            shuffled = false
            shufflePermutation = []
            currentIndex = currentCanonical
        }
    }

    mutating func setRepeatMode(_ mode: RepeatMode) {
        repeatMode = mode
    }

    // MARK: - Snapshot

    func snapshot() -> QueueSnapshot {
        QueueSnapshot(
            history: history,
            nowPlaying: nowPlaying,
            upcoming: upcoming,
            shuffled: shuffled,
            repeatMode: repeatMode,
        )
    }

    // MARK: - Private Helpers

    private mutating func removeCanonicalIndex(_ canonicalIndex: Int) {
        items.remove(at: canonicalIndex)

        // Adjust playedIndices: remove references and shift down
        playedIndices = playedIndices.compactMap { idx in
            if idx == canonicalIndex { return nil }
            return idx > canonicalIndex ? idx - 1 : idx
        }

        // Adjust shufflePermutation
        if shuffled {
            shufflePermutation = shufflePermutation.compactMap { idx in
                if idx == canonicalIndex { return nil }
                return idx > canonicalIndex ? idx - 1 : idx
            }
            // Adjust currentIndex if it now exceeds the permutation bounds
            if let ci = currentIndex, ci > shufflePermutation.count {
                currentIndex = max(0, shufflePermutation.count - 1)
            }
        } else {
            if let ci = currentIndex, canonicalIndex < ci {
                currentIndex = ci - 1
            } else if let ci = currentIndex, canonicalIndex == ci {
                // Shouldn't happen via upcoming removal, but handle gracefully
                if ci < items.count {
                    // currentIndex stays, now pointing at next item
                } else {
                    currentIndex = items.isEmpty ? nil : items.count - 1
                }
            }
        }
    }

    private func insertionPosition(forUpcomingIndex upcomingIndex: Int) -> Int {
        guard let ci = currentIndex else { return shufflePermutation.count }
        return min(ci + 1 + upcomingIndex, shufflePermutation.count)
    }

    private mutating func adjustPlayedIndicesAfterInsert(at insertedIndex: Int) {
        playedIndices = playedIndices.map { idx in
            idx >= insertedIndex ? idx + 1 : idx
        }
    }

    private mutating func rebuildPlayedIndicesAfterReorder(from source: Int, to dest: Int) {
        playedIndices = playedIndices.map { idx in
            if idx == source {
                return dest
            } else if source < dest, idx > source, idx <= dest {
                return idx - 1
            } else if source > dest, idx >= dest, idx < source {
                return idx + 1
            }
            return idx
        }
    }

    private mutating func rebuildShufflePermutationIndices() {
        // After removing items, canonical indices may have gaps.
        // Rebuild mapping so indices are contiguous 0..<items.count.
        // This is called after clearUpcoming which removes items.
        let canonicalSet = Set(0 ..< items.count)
        shufflePermutation = shufflePermutation.filter { canonicalSet.contains($0) }
    }
}
