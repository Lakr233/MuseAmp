//
//  ResponseCache.swift
//  AmMusicKit
//
//  Created by @Lakr233 on 2026/04/11.
//

import Foundation

actor ResponseCache<Value: Sendable> {
    private struct CacheEntry {
        let value: Value
        let cachedAt: Date
    }

    private var storage: [String: CacheEntry] = [:]

    func freshValue(forKey key: String, ttl: TimeInterval) -> Value? {
        guard let entry = storage[key],
              Date().timeIntervalSince(entry.cachedAt) < ttl
        else { return nil }
        return entry.value
    }

    func staleValue(forKey key: String, maxAge: TimeInterval = 7 * 24 * 3600) -> Value? {
        guard let entry = storage[key],
              Date().timeIntervalSince(entry.cachedAt) < maxAge
        else { return nil }
        return entry.value
    }

    func setValue(_ value: Value, forKey key: String) {
        storage[key] = CacheEntry(value: value, cachedAt: Date())
    }

    func setValue(_ value: Value, forKey key: String, cachedAt: Date) {
        storage[key] = CacheEntry(value: value, cachedAt: cachedAt)
    }
}
