@testable import AmMusic
import AmMusicPlayerKit
import Testing
import UIKit

@Suite(.serialized)
@MainActor
struct NowPlayingCompactControllerTests {
    @Test
    func `Now playing updates presentation state when track changes out of order`() throws {
        let sandbox = TestLibrarySandbox()
        let controller = NowPlayingCompactController(environment: sandbox.makeEnvironment())
        controller.loadViewIfNeeded()

        let firstArtworkURL = try makeArtworkFile(
            in: sandbox.baseDirectory,
            name: "first-artwork.png",
            color: UIColor(red: 1, green: 0, blue: 0, alpha: 1),
        )
        let secondArtworkURL = try makeArtworkFile(
            in: sandbox.baseDirectory,
            name: "second-artwork.png",
            color: UIColor(red: 0, green: 0, blue: 1, alpha: 1),
        )

        let firstSnapshot = makeNowPlayingSnapshot(
            trackID: "track-1",
            title: "Track 1",
            artworkURL: firstArtworkURL,
        )
        let secondSnapshot = makeNowPlayingSnapshot(
            trackID: "track-2",
            title: "Track 2",
            artworkURL: secondArtworkURL,
        )

        controller.applyPresentationSnapshot(firstSnapshot)

        controller.applyProgressSnapshot(secondSnapshot)
        controller.applyPresentationSnapshot(secondSnapshot)

        #expect(controller.currentPlaybackSnapshot.currentTrack?.id == "track-2")
    }
}

private func makeNowPlayingSnapshot(
    trackID: String,
    title: String,
    artworkURL: URL?,
) -> PlaybackSnapshot {
    let track = PlaybackTrack(
        id: trackID,
        title: title,
        artistName: "Artist",
        albumName: "Album",
        artworkURL: artworkURL,
        durationInSeconds: 180,
    )

    return PlaybackSnapshot(
        state: .playing,
        queue: [track],
        playerIndex: 0,
        currentTime: 0,
        duration: 180,
        repeatMode: .off,
        shuffled: false,
        source: .library,
        isCurrentTrackLiked: false,
        outputDevice: nil,
    )
}

private func makeArtworkFile(
    in directory: URL,
    name: String,
    color: UIColor,
) throws -> URL {
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4))
    let image = renderer.image { context in
        color.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
    }
    let data = try #require(image.pngData())
    let fileURL = directory.appendingPathComponent(name, isDirectory: false)
    try data.write(to: fileURL, options: .atomic)
    return fileURL
}
