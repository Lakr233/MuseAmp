//
//  DownloadArtworkProcessor.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import AmMusicDatabaseKit
@preconcurrency import AVFoundation
import Foundation

enum DownloadArtworkProcessor {
    private static let logger = "DownloadArtworkProcessor"

    static func prepareDownloadedTrack(
        trackID: String,
        fileURL: URL,
        artworkURL: URL?,
        apiClient: APIClient?,
        locations: LibraryPaths,
        session: URLSession = .shared,
    ) async {
        guard let artworkURL else {
            return
        }

        do {
            let artworkData = try await cachedArtworkData(
                trackID: trackID,
                artworkURL: artworkURL,
                apiClient: apiClient,
                locations: locations,
                session: session,
            )

            if try await hasEmbeddedArtwork(fileURL: fileURL) {
                return
            }

            try await embedArtwork(artworkData, into: fileURL)
        } catch {
            AppLog.warning(logger, "prepareDownloadedTrack failed trackID=\(trackID) error=\(error.localizedDescription)")
        }
    }
}

extension DownloadArtworkProcessor {
    enum ProcessingError: LocalizedError {
        case exportSessionUnavailable
        case unsupportedFileType(String)
        case exportFailed
        case exportTimedOut
        case fileUnreadable

        var errorDescription: String? {
            switch self {
            case .exportSessionUnavailable:
                "Unable to create export session"
            case let .unsupportedFileType(pathExtension):
                "Unsupported audio file type: \(pathExtension)"
            case .exportFailed:
                "Artwork export did not complete"
            case .exportTimedOut:
                "Export session timed out"
            case .fileUnreadable:
                "File is not readable or metadata cannot be loaded"
            }
        }
    }

    static func cachedArtworkData(
        trackID: String,
        artworkURL: URL,
        apiClient: APIClient?,
        locations: LibraryPaths,
        session: URLSession,
    ) async throws -> Data {
        let cacheURL = locations.artworkCacheURL(for: trackID)
        if FileManager.default.fileExists(atPath: cacheURL.path) {
            return try Data(contentsOf: cacheURL)
        }

        let request = apiClient?.authorizedRequest(URLRequest(url: artworkURL)) ?? URLRequest(url: artworkURL)
        let (data, _) = try await session.data(for: request)
        try data.write(to: cacheURL, options: .atomic)
        return data
    }

    static func hasEmbeddedArtwork(fileURL: URL) async throws -> Bool {
        try await withOverallTimeout(seconds: 30) {
            try await performHasEmbeddedArtwork(fileURL: fileURL)
        }
    }

    private static func performHasEmbeddedArtwork(fileURL: URL) async throws -> Bool {
        let asset = AVURLAsset(url: fileURL)
        let metadataItems = try await collectMetadataItems(from: asset)
        for item in metadataItems {
            guard matchesArtwork(item) else { continue }
            let hasData = await (try? item.load(.dataValue)) != nil
            let hasValue = await (try? item.load(.value)) != nil
            if hasData || hasValue {
                return true
            }
        }
        return false
    }

    static func embedArtwork(
        _ artworkData: Data,
        into fileURL: URL,
        timeout: TimeInterval = 30,
    ) async throws {
        guard FileManager.default.isReadableFile(atPath: fileURL.path) else {
            throw ProcessingError.fileUnreadable
        }
        try await withOverallTimeout(seconds: timeout) {
            try await performEmbedArtwork(
                artworkData,
                into: fileURL,
                exportTimeout: timeout,
            )
        }
    }

    static func withOverallTimeout<T: Sendable>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> T,
    ) async throws -> T {
        let once = ExportOnceGuard()
        let worker = Task(priority: .utility) {
            try await operation()
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, any Error>) in
                var timeoutWork: DispatchWorkItem?
                if seconds > 0 {
                    let work = DispatchWorkItem {
                        worker.cancel()
                        once.perform {
                            continuation.resume(throwing: ProcessingError.exportTimedOut)
                        }
                    }
                    timeoutWork = work
                    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + seconds, execute: work)
                }

                Task(priority: .utility) {
                    do {
                        let result = try await worker.value
                        timeoutWork?.cancel()
                        once.perform {
                            continuation.resume(returning: result)
                        }
                    } catch {
                        timeoutWork?.cancel()
                        once.perform {
                            continuation.resume(throwing: error)
                        }
                    }
                }
            }
        } onCancel: {
            worker.cancel()
        }
    }

    private static func performEmbedArtwork(
        _ artworkData: Data,
        into fileURL: URL,
        exportTimeout: TimeInterval,
    ) async throws {
        let asset = AVURLAsset(url: fileURL)
        guard await (try? asset.load(.isReadable)) == true else {
            throw ProcessingError.fileUnreadable
        }
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw ProcessingError.exportSessionUnavailable
        }

        let outputFileType = try resolveOutputFileType(for: fileURL, supportedTypes: exportSession.supportedFileTypes)
        let tempURL = temporaryOutputURL(for: fileURL)
        let metadata = try await collectMetadataItems(from: asset).filter { !matchesArtwork($0) } + artworkMetadataItems(data: artworkData)

        if FileManager.default.fileExists(atPath: tempURL.path) {
            do {
                try FileManager.default.removeItem(at: tempURL)
            } catch {
                AppLog.error(logger, "Failed to remove stale temp file: \(tempURL.path) error=\(error.localizedDescription)")
            }
        }

        exportSession.outputURL = tempURL
        exportSession.outputFileType = outputFileType
        exportSession.metadata = metadata
        exportSession.shouldOptimizeForNetworkUse = false

        do {
            try await export(exportSession, timeout: exportTimeout)
            _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: tempURL)
        } catch {
            if FileManager.default.fileExists(atPath: tempURL.path) {
                do {
                    try FileManager.default.removeItem(at: tempURL)
                } catch {
                    AppLog.error(logger, "Failed to remove temp file: \(tempURL.path) error=\(error.localizedDescription)")
                }
            }
            throw error
        }
    }

    static func collectMetadataItems(from asset: AVURLAsset) async throws -> [AVMetadataItem] {
        try await AVMetadataHelper.collectMetadataItems(from: asset)
    }

    static func export(_ exportSession: AVAssetExportSession) async throws {
        try await export(exportSession, timeout: 0)
    }

    static func export(_ exportSession: AVAssetExportSession, timeout: TimeInterval) async throws {
        let sessionBox = ExportSessionBox(exportSession)
        let once = ExportOnceGuard()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            var timeoutWork: DispatchWorkItem?
            if timeout > 0 {
                let work = DispatchWorkItem { [weak sessionBox] in
                    sessionBox?.session.cancelExport()
                    once.perform {
                        continuation.resume(throwing: ProcessingError.exportTimedOut)
                    }
                }
                timeoutWork = work
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: work)
            }

            sessionBox.session.exportAsynchronously {
                timeoutWork?.cancel()
                once.perform {
                    switch sessionBox.session.status {
                    case .completed:
                        continuation.resume()
                    case .failed:
                        continuation.resume(throwing: sessionBox.session.error ?? ProcessingError.exportFailed)
                    case .cancelled:
                        continuation.resume(throwing: sessionBox.session.error ?? CancellationError())
                    default:
                        continuation.resume(throwing: sessionBox.session.error ?? ProcessingError.exportFailed)
                    }
                }
            }
        }
    }

    static func resolveOutputFileType(for fileURL: URL, supportedTypes: [AVFileType]) throws -> AVFileType {
        let pathExtension = fileURL.pathExtension.lowercased()
        let preferredType: AVFileType? = switch pathExtension {
        case "m4a": .m4a
        case "mp4": .mp4
        default: nil
        }

        if let preferredType, supportedTypes.contains(preferredType) {
            return preferredType
        }
        if let firstSupportedType = supportedTypes.first {
            return firstSupportedType
        }

        throw ProcessingError.unsupportedFileType(pathExtension)
    }

    static func temporaryOutputURL(for fileURL: URL) -> URL {
        fileURL.deletingLastPathComponent()
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileURL.pathExtension)
    }

    final class ExportSessionBox: @unchecked Sendable {
        let session: AVAssetExportSession

        init(_ session: AVAssetExportSession) {
            self.session = session
        }
    }

    final class ExportOnceGuard: @unchecked Sendable {
        private let queue = DispatchQueue(label: "am.export.once")
        private var fired = false

        func perform(_ block: () -> Void) {
            let shouldFire: Bool = queue.sync {
                guard !fired else { return false }
                fired = true
                return true
            }
            if shouldFire { block() }
        }
    }

    static func matchesArtwork(_ item: AVMetadataItem) -> Bool {
        AVMetadataHelper.matches(item, tokens: ["artwork", "coverart", "covr"])
    }

    static func artworkMetadataItems(data: Data) -> [AVMetadataItem] {
        let commonItem = AVMutableMetadataItem()
        commonItem.identifier = .commonIdentifierArtwork
        commonItem.value = data as NSData
        commonItem.dataType = kCMMetadataBaseDataType_JPEG as String

        let iTunesItem = AVMutableMetadataItem()
        iTunesItem.identifier = .iTunesMetadataCoverArt
        iTunesItem.value = data as NSData
        iTunesItem.dataType = kCMMetadataBaseDataType_JPEG as String

        return [commonItem.copy() as! AVMetadataItem, iTunesItem.copy() as! AVMetadataItem]
    }
}
