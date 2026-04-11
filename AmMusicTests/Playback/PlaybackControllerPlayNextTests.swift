@testable import AmMusic
import AmMusicDatabaseKit
import AmMusicPlayerKit
import Foundation
import Testing

@Suite(.serialized)
@MainActor
struct PlaybackControllerPlayNextTests {
    @Test
    func `playNext returns alreadyPlaying when track is the current playing track`() async throws {
        let (controller, tracks) = try await makeControllerPlaying(trackCount: 2)

        let result = await controller.playNext([tracks[0]])

        #expect(result == .alreadyPlaying)
        #expect(controller.latestSnapshot.currentTrack?.id == tracks[0].id)
    }

    @Test
    func `playNext returns resumed when track is the current paused track`() async throws {
        let (controller, tracks) = try await makeControllerPlaying(trackCount: 2)
        controller.pause()
        #expect(controller.latestSnapshot.state == .paused)

        let result = await controller.playNext([tracks[0]])

        #expect(result == .resumed)
    }

    @Test
    func `playNext returns alreadyQueued when track is already next in queue`() async throws {
        let (controller, tracks) = try await makeControllerPlaying(trackCount: 2)

        let result = await controller.playNext([tracks[1]])

        #expect(result == .alreadyQueued)
        #expect(controller.latestSnapshot.upcoming.first?.id == tracks[1].id)
    }

    @Test
    func `playNext queues a new track that is not current and not next`() async throws {
        let (controller, tracks) = try await makeControllerPlaying(trackCount: 2)

        let newURL = try makeLocalAudioFile(
            locations: LibraryPaths(baseDirectory: controller.paths.baseDirectory),
            relativePath: "Artist/Album/New.wav",
        )
        let newTrack = PlaybackTrack(id: "new", title: "New", artistName: "Artist", localFileURL: newURL)

        let result = await controller.playNext([newTrack])

        guard case let .queued(count) = result else {
            Issue.record("Expected .queued, got \(result)")
            return
        }
        #expect(count == 1)
        #expect(controller.latestSnapshot.upcoming.first?.id == "new")
        #expect(controller.latestSnapshot.upcoming.map(\.id).contains(tracks[1].id))
    }

    @Test
    func `seek to zero rewinds current track`() async throws {
        let (controller, _) = try await makeControllerPlaying(trackCount: 1)

        controller.seek(to: 0)

        #expect(controller.latestSnapshot.currentTime == 0)
    }

    @Test
    func `next advances to next track when upcoming queue is non-empty`() async throws {
        let (controller, tracks) = try await makeControllerPlaying(trackCount: 3)
        #expect(controller.latestSnapshot.currentTrack?.id == tracks[0].id)

        controller.next()

        #expect(controller.latestSnapshot.currentTrack?.id == tracks[1].id)
    }

    // MARK: - Helpers

    private func makeControllerPlaying(trackCount: Int) async throws -> (PlaybackController, [PlaybackTrack]) {
        let sandbox = TestLibrarySandbox()
        let locations = LibraryPaths(baseDirectory: sandbox.baseDirectory)
        try locations.ensureDirectoriesExist()
        let database = try sandbox.makeDatabase()
        let downloadStore = DownloadStore(database: database, paths: locations)
        let playlistStore = PlaylistStore(database: database)
        let apiClient = try APIClient(baseURL: #require(URL(string: "https://example.com")))

        let controller = PlaybackController(
            apiClient: apiClient,
            database: database,
            downloadStore: downloadStore,
            metadataReader: EmbeddedMetadataReader(),
            paths: locations,
            playlistStore: playlistStore,
        )

        var tracks: [PlaybackTrack] = []
        for i in 0 ..< trackCount {
            let url = try makeLocalAudioFile(
                locations: locations,
                relativePath: "Artist/Album/Track\(i).wav",
            )
            tracks.append(PlaybackTrack(
                id: "track-\(i)",
                title: "Track \(i)",
                artistName: "Artist",
                localFileURL: url,
            ))
        }

        let started = await controller.play(tracks: tracks, source: .library)
        #expect(started == true)

        return (controller, tracks)
    }

    private func makeLocalAudioFile(
        locations: LibraryPaths,
        relativePath: String,
    ) throws -> URL {
        let fileURL = locations.absoluteAudioURL(for: relativePath)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        try makeSilentWAVData().write(to: fileURL)
        return fileURL
    }

    private func makeSilentWAVData(
        sampleRate: UInt32 = 8000,
        duration: TimeInterval = 30,
    ) -> Data {
        let channelCount: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let bytesPerSample = UInt32(bitsPerSample / 8)
        let frameCount = UInt32(max(Int((Double(sampleRate) * duration).rounded()), 1))
        let byteRate = sampleRate * UInt32(channelCount) * bytesPerSample
        let blockAlign = channelCount * UInt16(bytesPerSample)
        let dataSize = frameCount * UInt32(blockAlign)
        let riffChunkSize = 36 + dataSize

        var data = Data()
        data.append("RIFF".data(using: .ascii)!)
        data.append(littleEndianBytes(riffChunkSize))
        data.append("WAVE".data(using: .ascii)!)
        data.append("fmt ".data(using: .ascii)!)
        data.append(littleEndianBytes(UInt32(16)))
        data.append(littleEndianBytes(UInt16(1)))
        data.append(littleEndianBytes(channelCount))
        data.append(littleEndianBytes(sampleRate))
        data.append(littleEndianBytes(byteRate))
        data.append(littleEndianBytes(blockAlign))
        data.append(littleEndianBytes(bitsPerSample))
        data.append("data".data(using: .ascii)!)
        data.append(littleEndianBytes(dataSize))
        data.append(Data(count: Int(dataSize)))
        return data
    }

    private func littleEndianBytes<T: FixedWidthInteger>(_ value: T) -> Data {
        var littleEndianValue = value.littleEndian
        return Data(bytes: &littleEndianValue, count: MemoryLayout<T>.size)
    }

    private func settlePlaybackController() async {
        for _ in 0 ..< 3 {
            await Task.yield()
        }
    }
}

extension PlayNextResult: @retroactive Equatable {
    public static func == (lhs: PlayNextResult, rhs: PlayNextResult) -> Bool {
        switch (lhs, rhs) {
        case let (.played(l), .played(r)): l == r
        case let (.queued(l), .queued(r)): l == r
        case (.resumed, .resumed): true
        case (.alreadyPlaying, .alreadyPlaying): true
        case (.alreadyQueued, .alreadyQueued): true
        case (.failed, .failed): true
        default: false
        }
    }
}
