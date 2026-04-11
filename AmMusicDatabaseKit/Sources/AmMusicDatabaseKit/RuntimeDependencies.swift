//
//  RuntimeDependencies.swift
//  AmMusicDatabaseKit
//
//  Created by @Lakr233 on 2026/04/11.
//

import Foundation

public struct AudioFileInspection: Sendable {
    public let metadata: ImportedTrackMetadata
    public let embeddedArtwork: Data?

    public init(metadata: ImportedTrackMetadata, embeddedArtwork: Data?) {
        self.metadata = metadata
        self.embeddedArtwork = embeddedArtwork
    }
}

public struct RuntimeDependencies: Sendable {
    public let resolveDownloadURL: @Sendable (String) async throws -> URL
    public let requestHeaders: @Sendable (URL?) -> [String: String]
    public let fetchLyrics: @Sendable (String) async throws -> String?
    public let fetchArtworkData: @Sendable (URL) async throws -> Data?
    public let inspectAudioFile: @Sendable (URL) async throws -> AudioFileInspection
    public let setScreenAwake: @Sendable (Bool) -> Void

    public init(
        resolveDownloadURL: @escaping @Sendable (String) async throws -> URL,
        requestHeaders: @escaping @Sendable (URL?) -> [String: String],
        fetchLyrics: @escaping @Sendable (String) async throws -> String?,
        fetchArtworkData: @escaping @Sendable (URL) async throws -> Data?,
        inspectAudioFile: @escaping @Sendable (URL) async throws -> AudioFileInspection,
        setScreenAwake: @escaping @Sendable (Bool) -> Void,
    ) {
        self.resolveDownloadURL = resolveDownloadURL
        self.requestHeaders = requestHeaders
        self.fetchLyrics = fetchLyrics
        self.fetchArtworkData = fetchArtworkData
        self.inspectAudioFile = inspectAudioFile
        self.setScreenAwake = setScreenAwake
    }
}
