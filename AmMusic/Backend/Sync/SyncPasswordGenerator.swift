//
//  SyncPasswordGenerator.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import Foundation

nonisolated enum SyncPasswordGenerator {
    static func generate() -> String {
        String(format: "%06d", Int.random(in: 0 ..< 1_000_000))
    }
}
