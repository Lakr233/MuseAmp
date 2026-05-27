//
//  AudioFileImporter.swift
//  MuseAmp
//
//  Created by @Lakr233 on 2026/04/11.
//

import AVFoundation
import CryptoKit
import Foundation
import MuseAmpDatabaseKit
import UniformTypeIdentifiers

nonisolated struct AudioImportResult {
    let succeeded: Int
    let duplicates: Int
    let noMetadata: Int
    let errors: Int

    var total: Int {
        succeeded + duplicates + noMetadata + errors
    }
}

nonisolated struct AudioImportOptions {
    let allowsBackgroundArtworkFetch: Bool

    static let `default` = AudioImportOptions(allowsBackgroundArtworkFetch: true)
    static let offlineTransfer = AudioImportOptions(allowsBackgroundArtworkFetch: false)
}

final class AudioFileImporter: @unchecked Sendable {
    private let paths: LibraryPaths
    private let database: MusicLibraryDatabase
    private let metadataReader: EmbeddedMetadataReader
    private let apiClient: APIClient

    init(
        paths: LibraryPaths,
        database: MusicLibraryDatabase,
        metadataReader: EmbeddedMetadataReader,
        apiClient: APIClient,
    ) {
        self.paths = paths
        self.database = database
        self.metadataReader = metadataReader
        self.apiClient = apiClient
    }

    func importFiles(
        urls: [URL],
        progressCallback: (@MainActor (_ current: Int, _ total: Int) -> Void)? = nil,
    ) async -> AudioImportResult {
        await importFiles(
            urls: urls,
            options: .default,
            progressCallback: progressCallback,
        )
    }

    func importFiles(
        urls: [URL],
        options: AudioImportOptions,
        progressCallback: (@MainActor (_ current: Int, _ total: Int) -> Void)? = nil,
    ) async -> AudioImportResult {
        // Hold security-scoped access on the original picker URLs for the
        // entire import. Folder picks grant access to descendants through the
        // parent scope, so we must keep it alive until all reads/copies finish.
        var scopedURLs: [URL] = []
        for url in urls where url.startAccessingSecurityScopedResource() {
            scopedURLs.append(url)
        }
        defer { scopedURLs.forEach { $0.stopAccessingSecurityScopedResource() } }

        let audioFiles = discoverAudioFiles(from: urls)
        AppLog.info(
            self, "importFiles starting with \(audioFiles.count) audio file(s) from \(urls.count) URL(s)",
        )

        var succeeded = 0
        var duplicates = 0
        var noMetadata = 0
        var errors = 0
        var importedTracks: [ImportedTrack] = []

        let existingTracks: [AudioTrackRecord]
        do {
            existingTracks = try database.allTracks()
        } catch {
            AppLog.error(self, "importFiles failed to load existing tracks: \(error)")
            return AudioImportResult(succeeded: 0, duplicates: 0, noMetadata: 0, errors: audioFiles.count)
        }

        // Track metadata of successfully imported files within this batch so
        // that selecting the same track twice (directly + via containing
        // folder) does not produce two copies.
        var batchImported: Set<DuplicateKey> = []

        let totalFiles = audioFiles.count
        for (index, fileURL) in audioFiles.enumerated() {
            progressCallback?(index + 1, totalFiles)
            do {
                let result = try await importSingleFile(
                    fileURL: fileURL,
                    existingTracks: existingTracks,
                    batchImported: &batchImported,
                )
                switch result {
                case let .success(importedTrack):
                    succeeded += 1
                    importedTracks.append(importedTrack)
                case .duplicate:
                    duplicates += 1
                case .noMetadata:
                    noMetadata += 1
                }
            } catch {
                AppLog.error(self, "importFiles failed for '\(fileURL.lastPathComponent)': \(error)")
                errors += 1
            }
        }

        if succeeded > 0, options.allowsBackgroundArtworkFetch {
            enqueueBackgroundArtworkFetchesIfNeeded(for: importedTracks)
        }

        let result = AudioImportResult(
            succeeded: succeeded, duplicates: duplicates, noMetadata: noMetadata, errors: errors,
        )
        AppLog.info(
            self,
            "importFiles finished succeeded=\(succeeded) duplicates=\(duplicates) noMetadata=\(noMetadata) errors=\(errors)",
        )
        return result
    }
}

private extension AudioFileImporter {
    enum SingleImportResult {
        case success(ImportedTrack)
        case duplicate
        case noMetadata
    }

    struct ImportedTrack {
        let trackID: String
        let artworkURL: URL?
        let hasEmbeddedArtwork: Bool
    }

    struct DuplicateKey: Hashable {
        let title: String
        let artist: String
        let album: String
        let durationBucket: Int

        init(title: String, artist: String, album: String, duration: Double) {
            self.title = title.lowercased()
            self.artist = artist.lowercased()
            self.album = album.lowercased()
            // Bucket durations to the nearest 2s so ±1s tolerance matches
            durationBucket = Int((duration / 2.0).rounded())
        }
    }

    struct EmbeddedCatalogIDs {
        let trackID: String
        let albumID: String
        let artworkURL: URL?
        let isEmbedded: Bool
    }

    func importSingleFile(
        fileURL: URL,
        existingTracks: [AudioTrackRecord],
        batchImported: inout Set<DuplicateKey>,
    ) async throws -> SingleImportResult {
        let ext = fileURL.pathExtension.lowercased()
        let fileName = fileURL.deletingPathExtension().lastPathComponent

        let asset = AVURLAsset(url: fileURL)
        let duration = try await asset.load(.duration)
        let durationSeconds = max(CMTimeGetSeconds(duration), 0)
        let metadataItems = try await AVMetadataHelper.collectMetadataItems(from: asset)
        let fileSizeForLog = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber)?.int64Value ?? -1
        AppLog.info(
            self,
            "importSingleFile inspecting file='\(fileName)' ext=\(ext) durationSeconds=\(String(format: "%.2f", durationSeconds)) metadataItems=\(metadataItems.count) fileSize=\(fileSizeForLog)",
        )

        let sourceAttributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let fileSize = (sourceAttributes[.size] as? NSNumber)?.int64Value ?? 0
        let modifiedAt = sourceAttributes[.modificationDate] as? Date ?? .init()

        let previewRecord = try await metadataReader.makeTrackRecord(
            fileURL: fileURL,
            relativePath: fileName,
            trackID: "0",
            albumID: nil,
            fileSize: fileSize,
            modifiedAt: modifiedAt,
        )

        let catalogIDs: EmbeddedCatalogIDs
        if let embedded = await extractCatalogIDs(from: metadataItems) {
            catalogIDs = embedded
            AppLog.info(
                self,
                "importSingleFile extracted catalog metadata file='\(fileName)' trackID=\(embedded.trackID) albumID=\(embedded.albumID) hasArtworkURL=\(embedded.artworkURL != nil)",
            )
        } else {
            catalogIDs = try generatedCatalogIDs(
                for: fileURL,
                title: previewRecord.title,
                artistName: previewRecord.artistName,
                albumTitle: previewRecord.albumTitle,
                albumArtistName: previewRecord.albumArtistName,
            )
            AppLog.info(
                self,
                "importSingleFile generated catalog metadata file='\(fileName)' trackID=\(catalogIDs.trackID) albumID=\(catalogIDs.albumID)",
            )
        }

        let trackID = catalogIDs.trackID
        let albumID = catalogIDs.albumID

        let destinationRelativePath =
            "\(sanitizePathComponent(albumID))/\(sanitizePathComponent(trackID)).\(ext.isEmpty ? "m4a" : ext)"
        let destURL = paths.absoluteAudioURL(for: destinationRelativePath)
        if FileManager.default.fileExists(atPath: destURL.path) {
            AppLog.verbose(
                self, "importSingleFile file already exists trackID=\(trackID) albumID=\(albumID)",
            )
            return .duplicate
        }

        let inspectedRecord = try await metadataReader.makeTrackRecord(
            fileURL: fileURL,
            relativePath: destinationRelativePath,
            trackID: trackID,
            albumID: albumID,
            fileSize: fileSize,
            modifiedAt: modifiedAt,
        )

        let dupKey = DuplicateKey(
            title: inspectedRecord.title,
            artist: inspectedRecord.artistName,
            album: inspectedRecord.albumTitle,
            duration: inspectedRecord.durationSeconds,
        )

        if batchImported.contains(dupKey) {
            AppLog.verbose(
                self,
                "importSingleFile intra-batch duplicate title='\(inspectedRecord.title)' artist='\(inspectedRecord.artistName)'",
            )
            return .duplicate
        }

        if isDuplicate(
            title: inspectedRecord.title,
            artist: inspectedRecord.artistName,
            album: inspectedRecord.albumTitle,
            duration: inspectedRecord.durationSeconds,
            in: existingTracks,
        ) {
            AppLog.verbose(
                self,
                "importSingleFile duplicate title='\(inspectedRecord.title)' artist='\(inspectedRecord.artistName)'",
            )
            return .duplicate
        }

        let stagingURL = paths.incomingDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
            .appendingPathExtension(ext.isEmpty ? "m4a" : ext)
        try FileManager.default.createDirectory(
            at: paths.incomingDirectory,
            withIntermediateDirectories: true,
        )
        try FileManager.default.copyItem(at: fileURL, to: stagingURL)

        let embeddedLyrics = catalogIDs.isEmbedded ? await metadataReader.extractLyrics(from: metadataItems) : nil

        let metadata = ImportedTrackMetadata(
            trackID: trackID,
            albumID: albumID,
            title: inspectedRecord.title,
            artistName: inspectedRecord.artistName,
            albumTitle: inspectedRecord.albumTitle,
            albumArtistName: inspectedRecord.albumArtistName,
            durationSeconds: inspectedRecord.durationSeconds,
            trackNumber: inspectedRecord.trackNumber,
            discNumber: inspectedRecord.discNumber,
            genreName: inspectedRecord.genreName,
            composerName: inspectedRecord.composerName,
            releaseDate: inspectedRecord.releaseDate,
            lyrics: embeddedLyrics,
            sourceKind: .imported,
        )

        let ingestedRecord: AudioTrackRecord
        do {
            ingestedRecord = try await database.ingestAudioFile(url: stagingURL, metadata: metadata)
        } catch {
            if FileManager.default.fileExists(atPath: stagingURL.path) {
                try? FileManager.default.removeItem(at: stagingURL)
            }
            throw error
        }

        batchImported.insert(dupKey)
        return .success(
            ImportedTrack(
                trackID: trackID,
                artworkURL: catalogIDs.artworkURL,
                hasEmbeddedArtwork: ingestedRecord.hasEmbeddedArtwork,
            ),
        )
    }

    func extractCatalogIDs(from items: [AVMetadataItem]) async -> EmbeddedCatalogIDs? {
        for item in items {
            guard
                item.identifier == .iTunesMetadataUserComment
                || AVMetadataHelper.matches(item, tokens: ["comment", "cmt"])
            else { continue }
            guard let value = try? await item.load(.stringValue),
                  let data = value.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let trackID = json["trackID"] as? String, trackID.isCatalogID,
                  let albumID = json["albumID"] as? String, albumID.isCatalogID
            else {
                continue
            }
            let artworkURLString = (json["artworkURL"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let artworkURL: URL? = artworkURLString.flatMap { artworkURLString in
                guard !artworkURLString.isEmpty else {
                    return nil
                }
                guard let artworkURL = URL(string: artworkURLString) else {
                    AppLog.warning(
                        self, "extractCatalogIDs invalid artworkURL='\(artworkURLString)' trackID=\(trackID)",
                    )
                    return nil
                }
                return artworkURL
            }
            return EmbeddedCatalogIDs(trackID: trackID, albumID: albumID, artworkURL: artworkURL, isEmbedded: true)
        }
        return nil
    }

    func generatedCatalogIDs(
        for fileURL: URL,
        title: String,
        artistName: String,
        albumTitle: String,
        albumArtistName: String?,
    ) throws -> EmbeddedCatalogIDs {
        let fileData = try Data(contentsOf: fileURL)
        let albumGroupingArtist = albumArtistName?.nilIfEmpty ?? artistName
        let trackSeed = [
            "track",
            normalizedIdentityText(title),
            normalizedIdentityText(artistName),
            normalizedIdentityText(albumTitle),
            normalizedIdentityText(albumGroupingArtist),
            SHA256.hash(data: fileData).compactMap { String(format: "%02x", $0) }.joined(),
        ].joined(separator: "|")
        let albumSeed = [
            "album",
            normalizedIdentityText(albumTitle),
            normalizedIdentityText(albumGroupingArtist),
        ].joined(separator: "|")

        return EmbeddedCatalogIDs(
            trackID: numericIdentifier(from: trackSeed),
            albumID: numericIdentifier(from: albumSeed),
            artworkURL: nil,
            isEmbedded: false,
        )
    }

    func normalizedIdentityText(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()
    }

    func numericIdentifier(from seed: String) -> String {
        let digest = SHA256.hash(data: Data(seed.utf8))
        let value = digest.prefix(8).reduce(UInt64(0)) { partial, byte in
            (partial << 8) | UInt64(byte)
        }
        return String(value)
    }

    func isDuplicate(
        title: String, artist: String, album: String, duration: Double, in tracks: [AudioTrackRecord],
    ) -> Bool {
        tracks.contains { track in
            track.title.caseInsensitiveCompare(title) == .orderedSame
                && track.artistName.caseInsensitiveCompare(artist) == .orderedSame
                && track.albumTitle.caseInsensitiveCompare(album) == .orderedSame
                && abs(track.durationSeconds - duration) < 2.0
        }
    }

    func discoverAudioFiles(from urls: [URL]) -> [URL] {
        var files: [URL] = []
        let fm = FileManager.default

        for url in urls {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }

            if isDir.boolValue {
                guard
                    let enumerator = fm.enumerator(
                        at: url,
                        includingPropertiesForKeys: [.isRegularFileKey, .contentTypeKey],
                        options: [.skipsHiddenFiles],
                    )
                else { continue }

                for case let fileURL as URL in enumerator {
                    if isAudioFile(fileURL) {
                        files.append(fileURL)
                    }
                }
            } else if isAudioFile(url) {
                files.append(url)
            }
        }
        return files
    }

    func isAudioFile(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentTypeKey]),
              values.isRegularFile == true
        else { return false }

        if let contentType = values.contentType, contentType.conforms(to: .audio) {
            return true
        }

        let audioExtensions: Set = [
            "mp3", "m4a", "flac", "wav", "aac", "aiff", "alac", "ogg", "wma", "opus",
        ]
        return audioExtensions.contains(url.pathExtension.lowercased())
    }

    func extractString(in items: [AVMetadataItem], matching tokens: [String]) async
        -> String?
    {
        let loweredTokens = tokens.map { $0.lowercased() }
        for item in items {
            guard AVMetadataHelper.matches(item, tokens: loweredTokens) else { continue }
            if let value = try? await item.load(.stringValue)?.trimmingCharacters(
                in: .whitespacesAndNewlines,
            ),
                !value.isEmpty
            {
                return value
            }
        }
        return nil
    }

    func enqueueBackgroundArtworkFetchesIfNeeded(for importedTracks: [ImportedTrack]) {
        let candidates = importedTracks.filter { !$0.hasEmbeddedArtwork && $0.artworkURL != nil }
        guard !candidates.isEmpty else {
            return
        }

        AppLog.info(self, "importFiles enqueued background artwork fetches count=\(candidates.count)")
        let paths = paths
        let apiClient = apiClient
        Task.detached(priority: .utility) {
            for candidate in candidates {
                guard let artworkURL = candidate.artworkURL else {
                    continue
                }

                do {
                    let artworkData = try await DownloadArtworkProcessor.cachedArtworkData(
                        trackID: candidate.trackID,
                        artworkURL: artworkURL,
                        apiClient: apiClient,
                        locations: paths,
                        session: .shared,
                    )
                    guard !artworkData.isEmpty else {
                        AppLog.warning(
                            "AudioFileImporter",
                            "background artwork fetch returned empty data trackID=\(candidate.trackID)",
                        )
                        continue
                    }

                    AppLog.info(
                        "AudioFileImporter", "background artwork fetch succeeded trackID=\(candidate.trackID)",
                    )
                    await MainActor.run {
                        NotificationCenter.default.post(
                            name: .artworkDidUpdate,
                            object: nil,
                            userInfo: [AppNotificationUserInfoKey.trackIDs: [candidate.trackID]],
                        )
                    }
                } catch {
                    AppLog.warning(
                        "AudioFileImporter",
                        "background artwork fetch failed trackID=\(candidate.trackID) error=\(error.localizedDescription)",
                    )
                }
            }
        }
    }
}
