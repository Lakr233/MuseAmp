//
//  DiskCacheStorageProvider.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import AmMusicKit
import CryptoKit
import Foundation

actor DiskCacheStorageProvider: CacheStorageProvider {
    private let directory: URL

    private struct StoredEnvelope: Codable {
        let data: Data
        let cachedAt: Date
        let version: Int
    }

    init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func load(forKey key: String) -> CacheEnvelope? {
        let url = filePath(forKey: key)
        guard let fileData = try? Data(contentsOf: url) else {
            return nil
        }
        guard let stored = try? PropertyListDecoder().decode(StoredEnvelope.self, from: fileData) else {
            AppLog.warning(self, "load decode failure key=\(key) size=\(fileData.count)")
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return CacheEnvelope(data: stored.data, cachedAt: stored.cachedAt, version: stored.version)
    }

    func store(_ envelope: CacheEnvelope, forKey key: String) {
        let stored = StoredEnvelope(
            data: envelope.data, cachedAt: envelope.cachedAt, version: envelope.version,
        )
        guard let encoded = try? PropertyListEncoder().encode(stored) else {
            AppLog.warning(self, "store encode failure key=\(key) size=\(envelope.data.count)")
            return
        }
        let url = filePath(forKey: key)
        do {
            try encoded.write(to: url, options: .atomic)
        } catch {
            AppLog.error(self, "store failure key=\(key) error=\(error)")
        }
    }

    func remove(forKey key: String) {
        let url = filePath(forKey: key)
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            AppLog.warning(self, "remove failure key=\(key) error=\(error)")
        }
    }

    func removeAll() {
        let fileManager = FileManager.default

        guard
            let urls = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles,
            )
        else {
            AppLog.warning(self, "removeAll failed to enumerate cache directory")
            return
        }

        for url in urls where url.pathExtension == "cache" {
            do {
                try fileManager.removeItem(at: url)
            } catch {
                AppLog.warning(self, "removeAll failure path=\(url.lastPathComponent) error=\(error)")
            }
        }
    }

    // MARK: - Private

    private func filePath(forKey key: String) -> URL {
        let hash = SHA256.hash(data: Data(key.utf8))
        let hex = hash.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent("\(hex).cache")
    }
}
