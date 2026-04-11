//
//  AppEnvironment+Bootstrap.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import AmMusicDatabaseKit
import Foundation
import Kingfisher
import UIKit

extension AppEnvironment {
    static func initializeDatabaseManagerSynchronously(
        apiBaseURL: URL = AppPreferences.defaultAPIBaseURL,
        baseDirectory: URL? = nil,
    ) throws -> DatabaseManager {
        let paths = LibraryPaths(baseDirectory: baseDirectory)
        AppLog.bootstrap(with: paths)
        let apiClient = makeAPIClient(apiBaseURL: apiBaseURL)
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

    static func makeAPIClient(apiBaseURL: URL) -> APIClient {
        let cachesURL =
            FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let diskCacheProvider = DiskCacheStorageProvider(
            directory: cachesURL.appendingPathComponent("APIResponseCache", isDirectory: true),
        )
        return APIClient(baseURL: apiBaseURL, cacheStorageProvider: diskCacheProvider)
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
            requestHeaders: { url in
                apiClient.authorizationHeaders(for: url)
            },
            fetchLyrics: { trackID in
                try await apiClient.lyrics(id: trackID)
            },
            fetchArtworkData: { artworkURL in
                var request = URLRequest(url: artworkURL)
                for (header, value) in apiClient.authorizationHeaders(for: artworkURL) {
                    request.setValue(value, forHTTPHeaderField: header)
                }
                let (data, _) = try await URLSession.shared.data(for: request)
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

    static func configureImageRequestAuthorization(apiClient: APIClient) {
        let cache = ImageCache.default
        cache.memoryStorage.config.totalCostLimit = 100 * 1024 * 1024
        cache.memoryStorage.config.countLimit = 512
        cache.diskStorage.config.sizeLimit = 500 * 1024 * 1024

        let modifier = AnyModifier { request in
            apiClient.authorizedRequest(request)
        }

        KingfisherManager.shared.defaultOptions =
            KingfisherManager.shared.defaultOptions.filter { option in
                if case .requestModifier = option {
                    return false
                }
                return true
            } + [.requestModifier(modifier), .backgroundDecode]
    }
}
