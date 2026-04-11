//
//  AVMetadataHelper.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

@preconcurrency import AVFoundation
import Foundation

enum AVMetadataHelper {
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
}
