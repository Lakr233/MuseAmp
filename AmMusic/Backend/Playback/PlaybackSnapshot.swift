import AmMusicPlayerKit
import Foundation

nonisolated struct PlaybackSnapshot {
    let state: PlaybackState
    let queue: [PlaybackTrack]
    let playerIndex: Int?
    let currentTime: TimeInterval
    let duration: TimeInterval
    let repeatMode: RepeatMode
    let shuffled: Bool
    let source: PlaybackSource?
    let isCurrentTrackLiked: Bool
    let outputDevice: PlaybackOutputDevice?

    var currentTrack: PlaybackTrack? {
        guard let playerIndex,
              queue.indices.contains(playerIndex)
        else {
            return nil
        }
        return queue[playerIndex]
    }

    var history: [PlaybackTrack] {
        guard let playerIndex else {
            return []
        }
        return Array(queue.prefix(playerIndex))
    }

    var upcoming: [PlaybackTrack] {
        guard let playerIndex else {
            return []
        }
        let nextIndex = playerIndex + 1
        guard queue.indices.contains(nextIndex) else {
            return []
        }
        return Array(queue[nextIndex...])
    }

    static let empty = PlaybackSnapshot(
        state: .idle,
        queue: [],
        playerIndex: nil,
        currentTime: 0,
        duration: 0,
        repeatMode: .off,
        shuffled: false,
        source: nil,
        isCurrentTrackLiked: false,
        outputDevice: nil
    )
}
