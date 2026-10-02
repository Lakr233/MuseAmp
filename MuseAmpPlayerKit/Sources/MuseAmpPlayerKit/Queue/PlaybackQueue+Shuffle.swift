//
//  PlaybackQueue+Shuffle.swift
//  MuseAmpPlayerKit
//
//  Created by @Lakr233 on 2026/04/11.
//

extension PlaybackQueue {
    /// Generate a Fisher-Yates shuffle permutation of canonical indices.
    /// If `pinningCurrent` is non-nil, that canonical index is placed at position 0
    /// and the rest are shuffled after it.
    mutating func generateShufflePermutation(pinningCurrent: Int?) {
        var indices = Array(0 ..< items.count)

        // Remove already-played indices from the shuffle
        let playedSet = Set(playedIndices)
        indices.removeAll { playedSet.contains($0) }

        // Also remove the pinned current if present (we'll prepend it)
        if let pinned = pinningCurrent {
            indices.removeAll { $0 == pinned }
        }

        // Fisher-Yates shuffle
        for i in stride(from: indices.count - 1, through: 1, by: -1) {
            let j = Int.random(in: 0 ... i)
            indices.swapAt(i, j)
        }

        // Pin current at front
        if let pinned = pinningCurrent {
            indices.insert(pinned, at: 0)
        }

        // Prepend played indices (they're before current in the permutation)
        shufflePermutation = playedIndices + indices
    }
}
