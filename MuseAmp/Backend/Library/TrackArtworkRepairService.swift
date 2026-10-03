//
//  TrackArtworkRepairService.swift
//  MuseAmp
//
//  Created by @Lakr233 on 2026/04/12.
//

@preconcurrency import AVFoundation
import Foundation
import MuseAmpDatabaseKit
import SubsonicClientKit

final nonisolated class TrackArtworkRepairService: @unchecked Sendable {
    enum RepairError: LocalizedError {
        case missingLocalFile(String)
        case artworkUnavailable(String)
        case emptyArtworkData(String)
        case invalidHTTPStatus(Int)

        var errorDescription: String? {
            switch self {
            case let .missingLocalFile(trackID):
                "Local audio file is missing for track \(trackID)"
            case let .artworkUnavailable(trackID):
                "Couldn't find album artwork for track \(trackID)"
            case let .emptyArtworkData(trackID):
                "Album artwork download returned no data for track \(trackID)"
            case let .invalidHTTPStatus(statusCode):
                "Artwork download failed with status \(statusCode)"
            }
        }
    }

    private let paths: LibraryPaths
    private let apiClient: APIClient
    private let session: URLSession

    init(
        paths: LibraryPaths,
        apiClient: APIClient,
        session: URLSession = .shared,
    ) {
        self.paths = paths
        self.apiClient = apiClient
        self.session = session
    }

    func repairArtwork(for track: AudioTrackRecord) async throws {
        let fileURL = paths.absoluteAudioURL(for: track.relativePath)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            let error = RepairError.missingLocalFile(track.trackID)
            AppLog.error(self, "repairArtwork missing file trackID=\(track.trackID) relativePath=\(track.relativePath)")
            throw error
        }

        AppLog.info(self, "repairArtwork start trackID=\(track.trackID) albumID=\(track.albumID)")

        do {
            let artworkURL = try await resolveArtworkURL(for: track, fileURL: fileURL)
            let artworkData = try await redownloadArtworkData(
                trackID: track.trackID,
                from: artworkURL,
            )
            try await DownloadArtworkProcessor.embedArtwork(artworkData, into: fileURL)

            await MainActor.run {
                NotificationCenter.default.post(
                    name: .artworkDidUpdate,
                    object: nil,
                    userInfo: [AppNotificationUserInfoKey.trackIDs: [track.trackID]],
                )
            }

            AppLog.info(self, "repairArtwork success trackID=\(track.trackID)")
        } catch {
            AppLog.error(self, "repairArtwork failed trackID=\(track.trackID) error=\(error.localizedDescription)")
            throw error
        }
    }
}

extension TrackArtworkRepairService {
    nonisolated static func embeddedArtworkURL(fromComment comment: String) -> URL? {
        guard let data = comment.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawArtworkURL = (json["artworkURL"] as? String)?
              .trimmingCharacters(in: .whitespacesAndNewlines),
              !rawArtworkURL.isEmpty
        else {
            return nil
        }
        return URL(string: rawArtworkURL)
    }
}

private extension TrackArtworkRepairService {
    func resolveArtworkURL(
        for track: AudioTrackRecord,
        fileURL: URL,
    ) async throws -> URL {
        if let embeddedArtworkURL = try await embeddedArtworkURL(in: fileURL) {
            return embeddedArtworkURL
        }

        if track.trackID.isCatalogID,
           let song = try await apiClient.song(id: track.trackID),
           let artworkURL = apiClient.mediaURL(
               from: song.attributes.artwork?.url,
               width: 600,
               height: 600,
           )
        {
            return artworkURL
        }

        if track.albumID.isCatalogID,
           let album = try await apiClient.album(id: track.albumID),
           let artworkURL = apiClient.mediaURL(
               from: album.attributes.artwork?.url,
               width: 600,
               height: 600,
           )
        {
            return artworkURL
        }

        throw RepairError.artworkUnavailable(track.trackID)
    }

    func embeddedArtworkURL(in fileURL: URL) async throws -> URL? {
        let asset = AVURLAsset(url: fileURL)
        let metadataItems = try await AVMetadataHelper.collectMetadataItems(from: asset)

        for item in metadataItems {
            guard AVMetadataHelper.isComment(item) else {
                continue
            }

            guard let value = try? await item.load(.stringValue),
                  let artworkURL = Self.embeddedArtworkURL(fromComment: value)
            else {
                continue
            }

            return artworkURL
        }

        return nil
    }

    func redownloadArtworkData(
        trackID: String,
        from artworkURL: URL,
    ) async throws -> Data {
        let artworkData: Data
        if artworkURL.isFileURL {
            artworkData = try Data(contentsOf: artworkURL)
        } else {
            let (data, response) = try await session.data(for: URLRequest(url: artworkURL))
            if let response = response as? HTTPURLResponse,
               !(200 ..< 300).contains(response.statusCode)
            {
                throw RepairError.invalidHTTPStatus(response.statusCode)
            }
            artworkData = data
        }

        guard !artworkData.isEmpty else {
            throw RepairError.emptyArtworkData(trackID)
        }

        let cacheURL = paths.artworkCacheURL(for: trackID)
        try FileManager.default.createDirectory(
            at: cacheURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil,
        )
        try artworkData.write(to: cacheURL, options: .atomic)
        return artworkData
    }
}
