//
//  PlaybackState.swift
//  AmMusicPlayerKit
//
//  Created by @Lakr233 on 2026/04/11.
//

public enum PlaybackState: Sendable, Hashable {
    case idle
    case playing
    case paused
    case buffering
    case error(String)

    public var isActive: Bool {
        switch self {
        case .playing, .paused, .buffering: true
        case .idle, .error: false
        }
    }
}
