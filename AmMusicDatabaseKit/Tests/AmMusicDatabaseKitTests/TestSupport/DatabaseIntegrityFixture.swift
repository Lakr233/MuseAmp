import AmMusicDatabaseKit
import Foundation

private struct InspectionFailure: Error {}

actor InspectionProvider {
    private var failingTrackIDs: Set<String> = []
    private var metadataByTrackID: [String: ImportedTrackMetadata] = [:]

    func setFailure(trackID: String, enabled: Bool) {
        if enabled {
            failingTrackIDs.insert(trackID)
        } else {
            failingTrackIDs.remove(trackID)
        }
    }

    func setMetadata(_ metadata: ImportedTrackMetadata) {
        metadataByTrackID[metadata.trackID] = metadata
    }

    func inspect(fileURL: URL) throws -> AudioFileInspection {
        let trackID = fileURL.deletingPathExtension().lastPathComponent
        if failingTrackIDs.contains(trackID) {
            throw InspectionFailure()
        }

        let albumID = fileURL.deletingLastPathComponent().lastPathComponent
        let metadata =
            metadataByTrackID[trackID]
                ?? ImportedTrackMetadata(
                    trackID: trackID,
                    albumID: albumID,
                    title: "Title \(trackID)",
                    artistName: "Artist \(albumID)",
                    albumTitle: "Album \(albumID)",
                    sourceKind: .downloaded
                )
        return AudioFileInspection(metadata: metadata, embeddedArtwork: nil)
    }
}

struct DatabaseIntegrityFixture {
    let rootURL: URL
    let paths: LibraryPaths
    private let inspectionProvider = InspectionProvider()
    private let artworkBackupURL: URL?

    init() throws {
        let temporaryRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        rootURL = temporaryRoot.appendingPathComponent(
            "AmMusicDatabaseKitTests-\(UUID().uuidString)", isDirectory: true
        )
        paths = LibraryPaths(baseDirectory: rootURL)
        artworkBackupURL = try Self.prepareArtworkIsolation(at: paths.artworkCacheDirectory)
    }

    func makeManager(
        inspectAudioFile overrideInspectAudioFile: (@Sendable (URL) async throws -> AudioFileInspection)? =
            nil
    ) async -> DatabaseManager {
        let provider = inspectionProvider
        let dependencies = RuntimeDependencies(
            resolveDownloadURL: { _ in
                URL(fileURLWithPath: "/dev/null")
            },
            requestHeaders: { _ in [:] },
            fetchLyrics: { _ in nil },
            fetchArtworkData: { _ in nil },
            inspectAudioFile: overrideInspectAudioFile
                ?? { fileURL in
                    try await provider.inspect(fileURL: fileURL)
                },
            setScreenAwake: { _ in }
        )
        return DatabaseManager(baseDirectory: rootURL, dependencies: dependencies, logSink: nil)
    }

    func setInspectionFailure(trackID: String, enabled: Bool) async {
        await inspectionProvider.setFailure(trackID: trackID, enabled: enabled)
    }

    func setInspectionMetadata(_ metadata: ImportedTrackMetadata) async {
        await inspectionProvider.setMetadata(metadata)
    }

    func createIncomingAudioFile(name: String = "\(UUID().uuidString).m4a") throws -> URL {
        let incoming = rootURL.appendingPathComponent(name, isDirectory: false)
        try Data("fixture-audio".utf8).write(to: incoming, options: .atomic)
        return incoming
    }

    func createLibraryAudioFile(relativePath: String) throws -> URL {
        let fileURL = paths.audioDirectory.appendingPathComponent(relativePath, isDirectory: false)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        try Data("fixture-audio".utf8).write(to: fileURL, options: .atomic)
        return fileURL
    }

    func removeIndexDatabaseArtifacts() throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: paths.databaseDirectory.path) else {
            return
        }
        let files = try fileManager.contentsOfDirectory(
            at: paths.databaseDirectory, includingPropertiesForKeys: nil
        )
        for file in files where file.lastPathComponent.hasPrefix("library_index.sqlite") {
            try fileManager.removeItem(at: file)
        }
    }

    func cleanup() throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: rootURL.path) {
            try fileManager.removeItem(at: rootURL)
        }

        if fileManager.fileExists(atPath: paths.artworkCacheDirectory.path) {
            try fileManager.removeItem(at: paths.artworkCacheDirectory)
        }

        guard let artworkBackupURL else {
            return
        }
        guard fileManager.fileExists(atPath: artworkBackupURL.path) else {
            return
        }

        try fileManager.createDirectory(
            at: paths.artworkCacheDirectory.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        try fileManager.moveItem(at: artworkBackupURL, to: paths.artworkCacheDirectory)
    }

    private static func prepareArtworkIsolation(at artworkDirectory: URL) throws -> URL? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: artworkDirectory.path) else {
            return nil
        }

        let parent = artworkDirectory.deletingLastPathComponent()
        let backupURL = parent.appendingPathComponent(
            "LibraryArtwork-Backup-\(UUID().uuidString)", isDirectory: true
        )
        try fileManager.moveItem(at: artworkDirectory, to: backupURL)
        return backupURL
    }
}
