import Foundation
import SPIndicator

@MainActor
enum PlaybackFeedbackPresenter {
    static func presentPlaySuccess(
        tracks: [PlaybackTrack],
        startIndex: Int? = nil,
        shuffle: Bool = false
    ) {
        let title = shuffle ? String(localized: "Shuffle Play") : String(localized: "Now Playing")
        SPIndicator.present(
            title: title,
            message: playbackMessage(for: tracks, startIndex: startIndex, preferCountSummary: shuffle),
            preset: .done
        )
    }

    static func presentPlayNextSuccess(count: Int, tracks: [PlaybackTrack]) {
        guard count > 0 else {
            presentFailure(title: String(localized: "Play Next"))
            return
        }

        SPIndicator.present(
            title: String(localized: "Play Next"),
            message: queueMessage(for: tracks, count: count, fallback: String(localized: "Added to play next")),
            preset: .done
        )
    }

    static func presentAddToQueueSuccess(count: Int, tracks: [PlaybackTrack]) {
        guard count > 0 else {
            presentFailure(title: String(localized: "Add to Queue"))
            return
        }

        SPIndicator.present(
            title: String(localized: "Add to Queue"),
            message: queueMessage(for: tracks, count: count, fallback: String(localized: "Added to queue")),
            preset: .done
        )
    }

    static func presentFailure(title: String) {
        SPIndicator.present(
            title: title,
            message: String(localized: "No playable songs found."),
            preset: .error
        )
    }

    private static func playbackMessage(
        for tracks: [PlaybackTrack],
        startIndex: Int?,
        preferCountSummary: Bool
    ) -> String {
        guard !tracks.isEmpty else {
            return String(localized: "No playable songs found.")
        }

        if !preferCountSummary,
           let startIndex,
           tracks.indices.contains(startIndex)
        {
            return trackSummary(for: tracks[startIndex])
        }

        if !preferCountSummary, tracks.count == 1, let firstTrack = tracks.first {
            return trackSummary(for: firstTrack)
        }

        return countSummary(count: tracks.count)
    }

    private static func queueMessage(for tracks: [PlaybackTrack], count: Int, fallback: String) -> String {
        if count == 1, let firstTrack = tracks.first {
            return trackSummary(for: firstTrack)
        }
        return count > 1 ? countSummary(count: count) : fallback
    }

    private static func trackSummary(for track: PlaybackTrack) -> String {
        "\(track.title) · \(track.artistName)"
    }

    private static func countSummary(count: Int) -> String {
        count == 1 ? String(localized: "1 song") : String(localized: "\(count) songs")
    }
}
