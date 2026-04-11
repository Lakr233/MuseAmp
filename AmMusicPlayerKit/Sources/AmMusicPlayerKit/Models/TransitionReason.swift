//
//  TransitionReason.swift
//  AmMusicPlayerKit
//
//  Created by @Lakr233 on 2026/04/11.
//

public enum TransitionReason: Sendable {
    case natural
    case userNext
    case userPrevious
    case userSkip(toIndex: Int)
    case itemFailed
}
