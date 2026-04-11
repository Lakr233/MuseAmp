@testable import AmMusic
import AmMusicDatabaseKit
import Foundation
import Testing

@Suite(.serialized)
struct LibraryPathsTests {
    @Test
    func `ensureDirectoriesExist creates the expected library directories and caches`() throws {
        let sandbox = TestLibrarySandbox()
        let locations = LibraryPaths(baseDirectory: sandbox.baseDirectory)

        try locations.ensureDirectoriesExist()

        let manager = FileManager.default
        var isDirectory: ObjCBool = false

        #expect(manager.fileExists(atPath: locations.baseDirectory.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)

        isDirectory = false
        #expect(manager.fileExists(atPath: locations.audioDirectory.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)

        isDirectory = false
        #expect(manager.fileExists(atPath: locations.incomingDirectory.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)

        isDirectory = false
        #expect(manager.fileExists(atPath: locations.databaseDirectory.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)

        isDirectory = false
        #expect(manager.fileExists(atPath: locations.logsDirectory.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)

        isDirectory = false
        #expect(manager.fileExists(atPath: locations.artworkCacheDirectory.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)

        isDirectory = false
        #expect(manager.fileExists(atPath: locations.lyricsCacheDirectory.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)

        let artworkURL = locations.artworkCacheURL(for: " weird/track:one ")
        #expect(artworkURL.lastPathComponent == "weird_track_one.jpg")
    }

    @Test
    func `relativeAudioPath resolves files inside audio directory and falls back to file name for outside files`() throws {
        let sandbox = TestLibrarySandbox()
        let locations = LibraryPaths(baseDirectory: sandbox.baseDirectory)
        try locations.ensureDirectoriesExist()

        let relativePath = "Album A/01 - Intro.m4a"
        let audioFileURL = locations.absoluteAudioURL(for: relativePath)
        try FileManager.default.createDirectory(
            at: audioFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil,
        )
        try Data("audio".utf8).write(to: audioFileURL)

        #expect(locations.relativeAudioPath(for: audioFileURL) == relativePath)

        let externalFile = sandbox.baseDirectory.appendingPathComponent("outside-track.mp3")
        try Data("data".utf8).write(to: externalFile)
        #expect(locations.relativeAudioPath(for: externalFile) == "outside-track.mp3")
    }

    @Test
    func `inferredRelativePath sanitizes track IDs into the managed library layout`() {
        let sandbox = TestLibrarySandbox()
        let locations = LibraryPaths(baseDirectory: sandbox.baseDirectory)

        let path = locations.inferredRelativePath(for: "track:one")

        #expect(path == "unknown/track_one.m4a")
    }
}
