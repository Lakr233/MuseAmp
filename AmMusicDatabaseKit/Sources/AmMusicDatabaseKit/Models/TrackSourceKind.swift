//
//  TrackSourceKind.swift
//  AmMusicDatabaseKit
//
//  Created by @Lakr233 on 2026/04/11.
//

import Foundation

public enum TrackSourceKind: String, Sendable, Codable, Hashable {
    case downloaded
    case imported
    case restored
    case unknown
}
