//
//  AVMetadataHelper.swift
//  MuseAmp
//
//  Created by @Lakr233 on 2026/04/11.
//

@preconcurrency import AVFoundation
import Foundation

nonisolated enum AVMetadataHelper {
    static func collectMetadataItems(from asset: AVURLAsset) async throws -> [AVMetadataItem] {
        var items = try await asset.load(.commonMetadata)
        let formats = try await asset.load(.availableMetadataFormats)
        for format in formats {
            try await items.append(contentsOf: asset.loadMetadata(for: format))
        }
        return items
    }

    static func matches(_ item: AVMetadataItem, tokens: [String]) -> Bool {
        let identifier = item.identifier?.rawValue.lowercased() ?? ""
        let commonKey = item.commonKey?.rawValue.lowercased() ?? ""
        let key = (item.key as? String)?.lowercased() ?? (item.key as? NSString)?.lowercased ?? ""
        return tokens.contains { token in
            identifier.contains(token) || commonKey.contains(token) || key.contains(token)
        }
    }

    static func matchesExactly(_ item: AVMetadataItem, tokens: [String]) -> Bool {
        let normalizedTokens = Set(tokens.map(metadataKeyComponent))
        let fields = [
            item.identifier?.rawValue,
            item.commonKey?.rawValue,
            item.key as? String ?? (item.key as? NSString).map(String.init),
        ]
        return fields.compactMap { $0 }.contains {
            normalizedTokens.contains(metadataKeyComponent($0))
        }
    }

    static func integerValue(in items: [AVMetadataItem], matching tokens: [String]) async -> Int? {
        for item in items where matchesExactly(item, tokens: tokens) {
            if let string = try? await item.load(.stringValue) {
                let head = string.split(separator: "/").first.map(String.init) ?? string
                if let value = Int(head.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    return value
                }
            }
            if let number = try? await item.load(.numberValue)?.intValue {
                return number
            }
            if matchesExactly(item, tokens: ["trkn", "disk"]),
               let data = try? await item.load(.dataValue),
               data.count >= 4
            {
                let value = data.prefix(4).suffix(2).reduce(0) { ($0 << 8) | Int($1) }
                if value > 0 {
                    return value
                }
            }
        }
        return nil
    }

    private static func metadataKeyComponent(_ value: String) -> String {
        value.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .last(where: { !$0.isEmpty })?
            .lowercased() ?? ""
    }
}
