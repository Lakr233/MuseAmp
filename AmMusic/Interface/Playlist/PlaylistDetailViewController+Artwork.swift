//
//  PlaylistDetailViewController+Artwork.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import AmMusicDatabaseKit
import Foundation
import UIKit

private struct PlaylistLocalArtworkPrefetchJob {
    let trackID: String
    let localFileURL: URL
    let destinationURL: URL
    let remoteRequest: URLRequest?
    let metadataReader: EmbeddedMetadataReader
}

extension PlaylistDetailViewController {
    func playbackTrack(for entry: PlaylistEntry) -> PlaybackTrack? {
        guard let environment else {
            return nil
        }

        if let localTrack = environment.libraryDatabase.trackOrNil(byID: entry.trackID) {
            return localTrack.playbackTrack(paths: environment.paths)
        }

        return entry.playbackTrack(apiClient: environment.apiClient)
    }

    func artworkURL(for entry: PlaylistEntry) -> URL? {
        guard let environment else {
            return APIClient.resolveMediaURL(entry.artworkURL, width: 88, height: 88)
        }

        if let localTrack = environment.libraryDatabase.trackOrNil(byID: entry.trackID) {
            let localArtworkURL = environment.paths.artworkCacheURL(for: localTrack.trackID)
            guard FileManager.default.fileExists(atPath: localArtworkURL.path) else {
                return nil
            }
            return localArtworkURL
        }

        return environment.apiClient.mediaURL(from: entry.artworkURL, width: 88, height: 88)
    }

    func prefetchLocalArtworkIfNeeded() {
        guard let environment,
              let playlist
        else {
            localArtworkPrefetchTask?.cancel()
            localArtworkPrefetchTask = nil
            return
        }

        let jobs = playlist.songs.compactMap { entry -> PlaylistLocalArtworkPrefetchJob? in
            guard let localTrack = environment.libraryDatabase.trackOrNil(byID: entry.trackID) else {
                return nil
            }

            let destinationURL = environment.paths.artworkCacheURL(for: localTrack.trackID)
            guard FileManager.default.fileExists(atPath: destinationURL.path) == false else {
                return nil
            }

            let remoteRequest = environment.apiClient
                .mediaURL(from: entry.artworkURL, width: 600, height: 600)
                .map { environment.apiClient.authorizedRequest(URLRequest(url: $0)) }

            return PlaylistLocalArtworkPrefetchJob(
                trackID: localTrack.trackID,
                localFileURL: environment.paths.absoluteAudioURL(for: localTrack.relativePath),
                destinationURL: destinationURL,
                remoteRequest: remoteRequest,
                metadataReader: environment.metadataReader,
            )
        }

        guard jobs.isEmpty == false else {
            localArtworkPrefetchTask?.cancel()
            localArtworkPrefetchTask = nil
            return
        }

        localArtworkPrefetchTask?.cancel()
        localArtworkPrefetchTask = Task.detached(priority: .utility) { [weak self] in
            var didWriteArtwork = false

            for job in jobs {
                guard Task.isCancelled == false else {
                    break
                }

                let didWrite = await Self.ensureAppOwnedArtwork(for: job)
                didWriteArtwork = didWriteArtwork || didWrite
            }

            let shouldReload = didWriteArtwork
            await MainActor.run { [weak self, shouldReload] in
                guard let self else {
                    return
                }
                localArtworkPrefetchTask = nil
                guard shouldReload else {
                    return
                }
                applySnapshot()
            }
        }
    }
}

private extension PlaylistDetailViewController {
    nonisolated static func ensureAppOwnedArtwork(for job: PlaylistLocalArtworkPrefetchJob) async -> Bool {
        if FileManager.default.fileExists(atPath: job.destinationURL.path) {
            return false
        }

        if let artworkData = await job.metadataReader.extractArtwork(from: job.localFileURL) {
            do {
                try writeArtworkData(artworkData, to: job.destinationURL)
                AppLog.info("PlaylistDetailViewController", "stored embedded artwork trackID=\(job.trackID)")
                return true
            } catch {
                AppLog.error(
                    "PlaylistDetailViewController",
                    "store embedded artwork failed trackID=\(job.trackID) error=\(error.localizedDescription)",
                )
            }
        }

        guard let remoteRequest = job.remoteRequest else {
            return false
        }

        do {
            let (artworkData, _) = try await URLSession.shared.data(for: remoteRequest)
            try writeArtworkData(artworkData, to: job.destinationURL)
            AppLog.info("PlaylistDetailViewController", "stored remote artwork trackID=\(job.trackID)")
            return true
        } catch {
            AppLog.error(
                "PlaylistDetailViewController",
                "store remote artwork failed trackID=\(job.trackID) error=\(error.localizedDescription)",
            )
            return false
        }
    }

    nonisolated static func writeArtworkData(
        _ artworkData: Data,
        to destinationURL: URL,
    ) throws {
        try FileManager.default.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil,
        )
        try artworkData.write(to: destinationURL, options: .atomic)
    }
}
