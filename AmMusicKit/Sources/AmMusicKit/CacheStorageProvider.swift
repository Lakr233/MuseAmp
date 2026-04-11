//
//  CacheStorageProvider.swift
//  AmMusicKit
//
//  Created by @Lakr233 on 2026/04/11.
//

import Foundation

public struct CacheEnvelope: Sendable {
    public let data: Data
    public let cachedAt: Date
    public let version: Int

    public init(data: Data, cachedAt: Date, version: Int) {
        self.data = data
        self.cachedAt = cachedAt
        self.version = version
    }
}

public protocol CacheStorageProvider: Sendable {
    func load(forKey key: String) async -> CacheEnvelope?
    func store(_ envelope: CacheEnvelope, forKey key: String) async
    func remove(forKey key: String) async
    func removeAll() async
}
