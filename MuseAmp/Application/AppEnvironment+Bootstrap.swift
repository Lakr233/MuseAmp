//
//  AppEnvironment+Bootstrap.swift
//  MuseAmp
//
//  Created by @Lakr233 on 2026/04/11.
//

import Foundation
import Kingfisher
import MuseAmpDatabaseKit
import UIKit

extension AppEnvironment {
    /// Opens the journal in the default library at launch, so work that runs
    /// before the library boots is written to it instead of dropped.
    static func bootstrapLogging() {
        AppLog.bootstrap(with: LibraryPaths())
    }

    static func initializeDatabaseManagerSynchronously(
        apiBaseURL: URL = AppPreferences.defaultAPIBaseURL,
        baseDirectory: URL? = nil,
    ) throws -> DatabaseManager {
        let paths = LibraryPaths(baseDirectory: baseDirectory)
        AppLog.bootstrap(with: paths)
        let apiClient = APIClient(baseURL: apiBaseURL)
        let metadataReader = EmbeddedMetadataReader()
        let manager = DatabaseManager(
            baseDirectory: paths.baseDirectory,
            dependencies: makeRuntimeDependencies(
                apiClient: apiClient,
                metadataReader: metadataReader,
                paths: paths,
            ),
            logSink: { level, scope, message in
                switch level {
                case .verbose:
                    AppLog.verbose(scope, message)
                case .info:
                    AppLog.info(scope, message)
                case .warning:
                    AppLog.warning(scope, message)
                case .error, .critical:
                    AppLog.error(scope, message)
                }
            },
        )
        try manager.initializeSynchronously()
        return manager
    }

    static func initializeDatabaseManager(
        apiBaseURL: URL = AppPreferences.defaultAPIBaseURL,
        baseDirectory: URL? = nil,
    ) async throws -> DatabaseManager {
        try initializeDatabaseManagerSynchronously(
            apiBaseURL: apiBaseURL,
            baseDirectory: baseDirectory,
        )
    }

    static func makeRuntimeDependencies(
        apiClient: APIClient,
        metadataReader: EmbeddedMetadataReader,
        paths: LibraryPaths,
    ) -> RuntimeDependencies {
        RuntimeDependencies(
            resolveDownloadURL: { trackID in
                let playback = try await apiClient.playback(id: trackID)
                guard let resolvedURL = URL(string: playback.playbackURL) else {
                    throw NSError(domain: "AppEnvironment", code: 1)
                }
                return resolvedURL
            },
            requestHeaders: { _ in
                [:]
            },
            fetchLyrics: { trackID in
                try await apiClient.lyrics(id: trackID)
            },
            fetchArtworkData: { artworkURL in
                let (data, _) = try await URLSession.shared.data(for: URLRequest(url: artworkURL))
                return data.isEmpty ? nil : data
            },
            inspectAudioFile: { fileURL in
                let relativePath = paths.relativeAudioPath(for: fileURL)
                let pathParts = relativePath.split(separator: "/", maxSplits: 1).map(String.init)
                let albumID = pathParts.first
                let trackID = URL(fileURLWithPath: pathParts.last ?? fileURL.lastPathComponent)
                    .deletingPathExtension()
                    .lastPathComponent
                let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
                let fileSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
                let modifiedAt = attributes[.modificationDate] as? Date ?? .init()
                let record = try await metadataReader.makeTrackRecord(
                    fileURL: fileURL,
                    relativePath: relativePath,
                    trackID: trackID,
                    albumID: albumID,
                    fileSize: fileSize,
                    modifiedAt: modifiedAt,
                )
                let artwork = await metadataReader.extractArtwork(from: fileURL)
                let metadata = ImportedTrackMetadata(
                    trackID: record.trackID,
                    albumID: record.albumID,
                    title: record.title,
                    artistName: record.artistName,
                    albumTitle: record.albumTitle,
                    albumArtistName: record.albumArtistName,
                    durationSeconds: record.durationSeconds,
                    trackNumber: record.trackNumber,
                    discNumber: record.discNumber,
                    genreName: record.genreName,
                    composerName: record.composerName,
                    releaseDate: record.releaseDate,
                    lyrics: nil,
                    sourceKind: .unknown,
                )
                return AudioFileInspection(
                    metadata: metadata,
                    embeddedArtwork: artwork,
                )
            },
            setScreenAwake: { shouldKeepAwake in
                DispatchQueue.main.async {
                    UIApplication.shared.isIdleTimerDisabled = shouldKeepAwake
                }
            },
        )
    }

    /// Tracks indexed before Album Artist was read from file tags have none
    /// stored, and a library refresh skips unchanged files. Fill it in once,
    /// in the background, by re-reading only that tag.
    func backfillAlbumArtistsIfNeeded() {
        let databaseManager = databaseManager
        let metadataReader = metadataReader
        Task(priority: .utility) {
            do {
                try await databaseManager.backfillAlbumArtistsIfNeeded { fileURL in
                    await metadataReader.albumArtistName(at: fileURL)
                }
            } catch {
                AppLog.error("AppEnvironment", "backfillAlbumArtistsIfNeeded failed error=\(error.localizedDescription)")
            }
        }
    }

    static func configureImagePipeline() {
        let cache = ImageCache.default
        cache.memoryStorage.config.totalCostLimit = 100 * 1024 * 1024
        cache.memoryStorage.config.countLimit = 512
        cache.diskStorage.config.sizeLimit = 500 * 1024 * 1024

        KingfisherManager.shared.defaultOptions += [.backgroundDecode]
    }
}
