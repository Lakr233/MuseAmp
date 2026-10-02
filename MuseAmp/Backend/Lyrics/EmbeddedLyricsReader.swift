//
//  EmbeddedLyricsReader.swift
//  MuseAmp
//
//  Created by @Lakr233 on 2026/10/03.
//

@preconcurrency import AVFoundation
import Foundation

/// Reads the lyrics tag (`©lyr`) embedded in a local audio file.
nonisolated enum EmbeddedLyricsReader {
    /// Returns the trimmed embedded lyrics, or nil when the file is
    /// unreadable or carries no non-empty lyrics tag.
    static func lyrics(fromFileAt url: URL) async -> String? {
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            return nil
        }
        let asset = AVURLAsset(url: url)
        let items: [AVMetadataItem]
        do {
            items = try await AVMetadataHelper.collectMetadataItems(from: asset)
        } catch {
            AppLog.warning("EmbeddedLyricsReader", "metadata load failed file=\(url.lastPathComponent) error=\(error.localizedDescription)")
            return nil
        }
        for item in items {
            guard AVMetadataHelper.isLyrics(item) else { continue }
            if let value = await loadText(of: item, fileName: url.lastPathComponent) {
                return value
            }
        }
        return nil
    }

    /// The item's trimmed, non-empty text: its string value, or else its raw
    /// value when that is a string. A load failure is logged and falls
    /// through to the next source.
    private static func loadText(of item: AVMetadataItem, fileName: String) async -> String? {
        do {
            if let value = try await item.load(.stringValue)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty
            {
                return value
            }
        } catch {
            AppLog.warning("EmbeddedLyricsReader", "lyrics item string load failed file=\(fileName) error=\(error.localizedDescription)")
        }
        do {
            if let value = try await item.load(.value) as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        } catch {
            AppLog.warning("EmbeddedLyricsReader", "lyrics item value load failed file=\(fileName) error=\(error.localizedDescription)")
        }
        return nil
    }
}
