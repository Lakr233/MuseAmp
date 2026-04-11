//
//  SearchType.swift
//  AmMusicKit
//
//  Created by @Lakr233 on 2026/04/11.
//

import Foundation

public enum SearchType: String, CaseIterable, Sendable {
    case song
    case album
    case artist

    public var title: String {
        switch self {
        case .song:
            String(localized: "Songs", bundle: .module)
        case .album:
            String(localized: "Albums", bundle: .module)
        case .artist:
            String(localized: "Artists", bundle: .module)
        }
    }
}
