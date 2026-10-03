//
//  DatabaseManager+Support.swift
//  MuseAmpDatabaseKit
//
//  Created by @Lakr233 on 2026/04/11.
//

import Foundation

extension DatabaseManager {
    func requireIndexStore() throws -> IndexStore {
        guard let indexStore else {
            throw notInitializedError()
        }
        return indexStore
    }

    func requireStateStore() throws -> StateStore {
        guard let stateStore else {
            throw notInitializedError()
        }
        return stateStore
    }

    private func notInitializedError() -> NSError {
        NSError(
            domain: "DatabaseManager",
            code: 0,
            userInfo: [
                NSLocalizedDescriptionKey: String(
                    localized: "DatabaseManager is not initialized",
                    bundle: .module,
                ),
            ],
        )
    }

    func libraryScanner() throws -> LibraryScanner {
        try LibraryScanner(
            paths: paths,
            indexStore: requireIndexStore(),
            cacheCoordinator: cacheCoordinator,
            fileManager: fileManager,
            dependencies: dependencies,
            logger: logger,
        )
    }

    func fileSize(at url: URL) -> Int64 {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return 0
        }
        return (attributes[.size] as? NSNumber)?.int64Value ?? 0
    }

    func tempFileCount() -> Int {
        let urls =
            (try? FileManager.default.contentsOfDirectory(
                at: paths.audioDirectory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles],
            )) ?? []
        return urls.reduce(into: 0) { count, url in
            if url.lastPathComponent.hasSuffix(".tmp") {
                count += 1
            }
        }
    }

    func buildAuditIssues(
        orphanArtwork: Int,
        orphanLyrics: Int,
        invalidPathsFound: Int,
        unresolvedPlaylistEntries: Int,
    ) -> [AuditIssue] {
        var issues: [AuditIssue] = []
        if invalidPathsFound > 0 {
            issues.append(
                .init(
                    severity: .warning, code: "invalid_paths",
                    message: String(
                        format: String(localized: "Found %ld invalid library paths", bundle: .module),
                        locale: .current,
                        invalidPathsFound,
                    ),
                ),
            )
        }
        if orphanArtwork > 0 {
            issues.append(
                .init(
                    severity: .warning, code: "orphan_artwork",
                    message: String(
                        format: String(localized: "Found %ld orphan artwork files", bundle: .module),
                        locale: .current,
                        orphanArtwork,
                    ),
                ),
            )
        }
        if orphanLyrics > 0 {
            issues.append(
                .init(
                    severity: .warning, code: "orphan_lyrics",
                    message: String(
                        format: String(localized: "Found %ld orphan lyrics files", bundle: .module),
                        locale: .current,
                        orphanLyrics,
                    ),
                ),
            )
        }
        if unresolvedPlaylistEntries > 0 {
            issues.append(
                .init(
                    severity: .info, code: "unresolved_playlist_entries",
                    message: String(
                        format: String(
                            localized: "Found %ld playlist entries without backing files",
                            bundle: .module,
                        ),
                        locale: .current,
                        unresolvedPlaylistEntries,
                    ),
                ),
            )
        }
        return issues
    }
}
