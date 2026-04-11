//
//  LocalizationTests.swift
//  AmMusicDatabaseKit
//
//  Created by @Lakr233 on 2026/04/11.
//

import AmMusicDatabaseKit
import Foundation
import Testing

struct LocalizationTests {
    @Test
    func `DatabaseManager surfaces localized not-initialized error`() async {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("AmMusicDatabaseKit-L10n-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let manager = DatabaseManager(
            baseDirectory: root,
            dependencies: RuntimeDependencies(
                resolveDownloadURL: { _ in URL(fileURLWithPath: "/dev/null") },
                requestHeaders: { _ in [:] },
                fetchLyrics: { _ in nil },
                fetchArtworkData: { _ in nil },
                inspectAudioFile: { _ in
                    AudioFileInspection(
                        metadata: ImportedTrackMetadata(
                            trackID: "track",
                            albumID: "album",
                            title: "Title",
                            artistName: "Artist",
                            albumTitle: "Album",
                            sourceKind: .downloaded,
                        ),
                        embeddedArtwork: nil,
                    )
                },
                setScreenAwake: { _ in },
            ),
        )

        do {
            _ = try await manager.auditSnapshot()
            Issue.record("Expected auditSnapshot() to throw before initialization")
        } catch {
            let nsError = error as NSError
            #expect(
                nsError.localizedDescription == localizedDatabaseKitString(
                    "DatabaseManager is not initialized",
                ),
            )
        }
    }

    private func localizedDatabaseKitString(_ key: String) -> String {
        let bundles = Bundle.allBundles + Bundle.allFrameworks
        guard
            let resourceBundle = bundles.first(where: {
                $0.bundleURL.lastPathComponent == "AmMusicDatabaseKit_AmMusicDatabaseKit.bundle"
            })
        else {
            Issue.record("Expected AmMusicDatabaseKit resource bundle to be loaded")
            return key
        }
        return resourceBundle.localizedString(forKey: key, value: nil, table: nil)
    }
}
