@testable import AmMusic
import AmMusicDatabaseKit
import Foundation
import Testing
import UIKit

@Suite(.serialized)
struct PlaylistCoverArtworkCacheTests {
    private let cacheDirectory: URL
    private let artworkDirectory: URL
    private let cache: PlaylistCoverArtworkCache

    init() {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("CoverArtworkCacheTests-\(UUID().uuidString)", isDirectory: true)
        cacheDirectory = base.appendingPathComponent("Cache", isDirectory: true)
        artworkDirectory = base.appendingPathComponent("Artwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: artworkDirectory, withIntermediateDirectories: true)
        cache = PlaylistCoverArtworkCache(directory: cacheDirectory)
    }

    // MARK: - Helpers

    private func makePlaylist(songCount: Int, artworkPrefix _: String = "art") -> Playlist {
        let entries = (0 ..< songCount).map { index in
            PlaylistEntry(
                trackID: "track-\(index)",
                title: "Song \(index)",
                artistName: "Artist \(index)",
                albumID: "album-\(index)",
                artworkURL: nil,
            )
        }
        return Playlist(
            id: UUID(),
            name: "Test Playlist",
            entries: entries,
            createdAt: Date(),
            updatedAt: Date(),
        )
    }

    private func writeTestArtwork(for trackID: String) throws -> URL {
        let url = artworkDirectory.appendingPathComponent("\(trackID).jpg", isDirectory: false)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10))
        let image = renderer.image { context in
            UIColor(
                red: CGFloat.random(in: 0 ... 1),
                green: CGFloat.random(in: 0 ... 1),
                blue: CGFloat.random(in: 0 ... 1),
                alpha: 1,
            ).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        }
        try image.jpegData(compressionQuality: 0.8)?.write(to: url, options: .atomic)
        return url
    }

    private func localArtworkResolver(entry: PlaylistEntry, width _: Int, height _: Int) -> URL? {
        let url = artworkDirectory.appendingPathComponent("\(entry.trackID).jpg", isDirectory: false)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func diskCacheFiles() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: cacheDirectory.path) else {
            return []
        }
        return try FileManager.default.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: nil,
        )
    }

    // MARK: - Tests

    @Test
    func `Generated image has correct dimensions`() async throws {
        let playlist = makePlaylist(songCount: 4)
        for entry in playlist.songs {
            try writeTestArtwork(for: entry.trackID)
        }

        let image = await cache.image(
            for: playlist,
            sideLength: 100,
            scale: 1,
            urlResolver: localArtworkResolver,
        )

        #expect(image.size.width == 100)
        #expect(image.size.height == 100)
    }

    @Test
    func `Generated image is cached to disk`() async throws {
        let playlist = makePlaylist(songCount: 1)
        try writeTestArtwork(for: "track-0")

        _ = await cache.image(
            for: playlist,
            sideLength: 50,
            scale: 1,
            urlResolver: localArtworkResolver,
        )

        let files = try diskCacheFiles().filter { $0.pathExtension == "png" }
        #expect(files.count == 1)
    }

    @Test
    func `Invalidate cache removes disk files for playlist`() async throws {
        let playlist = makePlaylist(songCount: 1)
        try writeTestArtwork(for: "track-0")

        _ = await cache.image(
            for: playlist,
            sideLength: 50,
            scale: 1,
            urlResolver: localArtworkResolver,
        )

        let filesBefore = try diskCacheFiles().filter { $0.pathExtension == "png" }
        #expect(filesBefore.count == 1)

        await cache.invalidateCache(for: playlist)

        let filesAfter = try diskCacheFiles().filter { $0.pathExtension == "png" }
        #expect(filesAfter.isEmpty)
    }

    @Test
    func `Invalidate cache does not remove files for other playlists`() async throws {
        let playlist1 = makePlaylist(songCount: 1)
        let playlist2 = makePlaylist(songCount: 1)
        try writeTestArtwork(for: "track-0")

        _ = await cache.image(for: playlist1, sideLength: 50, scale: 1, urlResolver: localArtworkResolver)
        _ = await cache.image(for: playlist2, sideLength: 50, scale: 1, urlResolver: localArtworkResolver)

        let filesBefore = try diskCacheFiles().filter { $0.pathExtension == "png" }
        #expect(filesBefore.count == 2)

        await cache.invalidateCache(for: playlist1)

        let filesAfter = try diskCacheFiles().filter { $0.pathExtension == "png" }
        #expect(filesAfter.count == 1)
    }

    @Test
    func `Shuffled flag skips disk cache and regenerates`() async throws {
        let playlist = makePlaylist(songCount: 1)
        try writeTestArtwork(for: "track-0")

        var resolverCallCount = 0
        let countingResolver: (PlaylistEntry, Int, Int) -> URL? = { [artworkDirectory] entry, _, _ in
            resolverCallCount += 1
            let url = artworkDirectory.appendingPathComponent("\(entry.trackID).jpg", isDirectory: false)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }

        _ = await cache.image(for: playlist, sideLength: 50, scale: 1, urlResolver: countingResolver)
        #expect(resolverCallCount == 1)

        _ = await cache.image(for: playlist, sideLength: 50, scale: 1, urlResolver: countingResolver)
        #expect(resolverCallCount == 1) // served from cache

        _ = await cache.image(for: playlist, sideLength: 50, scale: 1, shuffled: true, urlResolver: countingResolver)
        #expect(resolverCallCount == 2) // regenerated
    }

    @Test
    func `Resolver receives full PlaylistEntry with trackID`() async throws {
        let playlist = makePlaylist(songCount: 4)
        for entry in playlist.songs {
            try writeTestArtwork(for: entry.trackID)
        }

        var receivedTrackIDs: [String] = []
        let trackingResolver: (PlaylistEntry, Int, Int) -> URL? = { [artworkDirectory] entry, _, _ in
            receivedTrackIDs.append(entry.trackID)
            let url = artworkDirectory.appendingPathComponent("\(entry.trackID).jpg", isDirectory: false)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }

        _ = await cache.image(for: playlist, sideLength: 50, scale: 1, urlResolver: trackingResolver)

        #expect(receivedTrackIDs.contains("track-0"))
        #expect(receivedTrackIDs.contains("track-1"))
        #expect(receivedTrackIDs.contains("track-2"))
        #expect(receivedTrackIDs.contains("track-3"))
    }

    @Test
    func `Image generated without artwork uses placeholder`() async {
        let playlist = makePlaylist(songCount: 4)
        // No artwork files written — resolver returns nil for all

        let image = await cache.image(
            for: playlist,
            sideLength: 100,
            scale: 1,
            urlResolver: localArtworkResolver,
        )

        #expect(image.size.width == 100)
        #expect(image.size.height == 100)
    }

    @Test
    func `Empty playlist generates single-tile image`() async {
        let playlist = makePlaylist(songCount: 0)

        let image = await cache.image(
            for: playlist,
            sideLength: 100,
            scale: 1,
            urlResolver: localArtworkResolver,
        )

        #expect(image.size.width == 100)
        #expect(image.size.height == 100)
    }
}
