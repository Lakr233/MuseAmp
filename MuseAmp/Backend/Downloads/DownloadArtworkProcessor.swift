//
//  DownloadArtworkProcessor.swift
//  MuseAmp
//
//  Created by @Lakr233 on 2026/04/11.
//

@preconcurrency import AVFoundation
import Foundation
import MuseAmpDatabaseKit

enum DownloadArtworkProcessor {
    private static let logger = "DownloadArtworkProcessor"

    static func prepareDownloadedTrack(
        trackID: String,
        fileURL: URL,
        artworkURL: URL?,
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
        locations: LibraryPaths,
        session: URLSession,
    ) async throws -> Data {
        let cacheURL = locations.artworkCacheURL(for: trackID)
        if FileManager.default.fileExists(atPath: cacheURL.path) {
            return try Data(contentsOf: cacheURL)
        }

        let (data, _) = try await session.data(for: URLRequest(url: artworkURL))
        try data.write(to: cacheURL, options: .atomic)
        return data
    }

    static func hasEmbeddedArtwork(fileURL: URL) async throws -> Bool {
        try await withOverallTimeout(seconds: 30) {
            try await performHasEmbeddedArtwork(fileURL: fileURL)
        }
    }

    private static func performHasEmbeddedArtwork(fileURL: URL) async throws -> Bool {
        try await containsArtwork(AVMetadataHelper.collectMetadataItems(from: AVURLAsset(url: fileURL)))
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
        try await withCheckedThrowingContinuation { continuation in
            _withOverallTimeout(seconds: seconds, operation: operation) { result in
                continuation.resume(with: result)
            }
        }
    }

    private nonisolated static func _withOverallTimeout<T: Sendable>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> T,
        completion: @escaping @Sendable (Result<T, any Error>) -> Void,
    ) {
        let once = OnceGuard()
        let worker = Task(priority: .utility) { try await operation() }

        var timeoutWork: DispatchWorkItem?
        if seconds > 0 {
            let work = DispatchWorkItem {
                worker.cancel()
                once.perform { completion(.failure(ProcessingError.exportTimedOut)) }
            }
            timeoutWork = work
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + seconds, execute: work)
        }

        Task(priority: .utility) {
            do {
                let result = try await worker.value
                timeoutWork?.cancel()
                once.perform { completion(.success(result)) }
            } catch {
                timeoutWork?.cancel()
                once.perform { completion(.failure(error)) }
            }
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
        let metadata = try await AVMetadataHelper.collectMetadataItems(from: asset).filter { !matchesArtwork($0) }
            + artworkMetadataItems(data: artworkData)

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

    static func export(_ exportSession: AVAssetExportSession, timeout: TimeInterval) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            _export(exportSession, timeout: timeout) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    // nonisolated: the timeout work item runs on a global queue. Inheriting
    // the default MainActor isolation makes Swift trap when it fires.
    private nonisolated static func _export(
        _ exportSession: AVAssetExportSession,
        timeout: TimeInterval,
        completion: @escaping @Sendable ((any Error)?) -> Void,
    ) {
        let sessionBox = UncheckedSendableBox(exportSession)
        let once = OnceGuard()

        var timeoutWork: DispatchWorkItem?
        if timeout > 0 {
            let work = DispatchWorkItem { [weak sessionBox] in
                // Claim the result before cancelling: cancelExport can run the
                // completion handler first, which would report a plain
                // cancellation instead of the timeout.
                once.perform { completion(ProcessingError.exportTimedOut) }
                sessionBox?.value.cancelExport()
            }
            timeoutWork = work
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: work)
        }

        let capturedTimeoutWork = timeoutWork
        sessionBox.value.exportAsynchronously { [once, sessionBox] in
            capturedTimeoutWork?.cancel()
            once.perform {
                switch sessionBox.value.status {
                case .completed:
                    completion(nil)
                case .failed:
                    completion(sessionBox.value.error ?? ProcessingError.exportFailed)
                case .cancelled:
                    completion(sessionBox.value.error ?? CancellationError())
                default:
                    completion(sessionBox.value.error ?? ProcessingError.exportFailed)
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

    static func matchesArtwork(_ item: AVMetadataItem) -> Bool {
        AVMetadataHelper.matches(item, tokens: ["artwork", "coverart", "covr"])
    }

    static func containsArtwork(_ items: [AVMetadataItem]) async -> Bool {
        for item in items {
            guard DownloadArtworkProcessor.matchesArtwork(item) else { continue }
            let hasData = await (try? item.load(.dataValue)) != nil
            let hasValue = await (try? item.load(.value)) != nil
            if hasData || hasValue {
                return true
            }
        }
        return false
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
