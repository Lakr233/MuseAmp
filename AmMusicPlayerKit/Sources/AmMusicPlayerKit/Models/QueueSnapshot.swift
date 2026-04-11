//
//  QueueSnapshot.swift
//  AmMusicPlayerKit
//
//  Created by @Lakr233 on 2026/04/11.
//

public struct QueueSnapshot: Sendable {
    public let history: [PlayerItem]
    public let nowPlaying: PlayerItem?
    public let upcoming: [PlayerItem]
    public let shuffled: Bool
    public let repeatMode: RepeatMode

    public var orderedItems: [PlayerItem] {
        guard let nowPlaying else {
            return history + upcoming
        }
        return history + [nowPlaying] + upcoming
    }

    public var currentIndex: Int? {
        nowPlaying == nil ? nil : history.count
    }

    public var totalCount: Int {
        orderedItems.count
    }
}
