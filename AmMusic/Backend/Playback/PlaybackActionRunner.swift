//
//  PlaybackActionRunner.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import Foundation

@MainActor
struct PlaybackActionRunner {
    let playbackController: PlaybackController

    @discardableResult
    func play(
        tracks: [PlaybackTrack],
        startAt startIndex: Int = 0,
        source: PlaybackSource,
        shuffle: Bool = false,
    ) async -> Bool {
        let didPlay = await playbackController.play(
            tracks: tracks,
            startAt: startIndex,
            source: source,
            shuffle: shuffle,
        )
        if didPlay {
            PlaybackFeedbackPresenter.presentPlaySuccess(
                tracks: tracks,
                startIndex: shuffle ? nil : startIndex,
                shuffle: shuffle,
            )
        } else {
            let title = shuffle ? String(localized: "Shuffle Play") : String(localized: "Play")
            PlaybackFeedbackPresenter.presentFailure(title: title)
        }
        return didPlay
    }

    @discardableResult
    func play(
        track: PlaybackTrack,
        in tracks: [PlaybackTrack],
        source: PlaybackSource,
    ) async -> Bool {
        let startIndex = tracks.firstIndex(of: track) ?? 0
        return await play(tracks: tracks, startAt: startIndex, source: source)
    }

    @discardableResult
    func playNext(_ tracks: [PlaybackTrack]) async -> PlayNextResult {
        let result = await playbackController.playNext(tracks)
        PlaybackFeedbackPresenter.presentPlayNextResult(result, tracks: tracks)
        return result
    }

    @discardableResult
    func addToQueue(_ tracks: [PlaybackTrack]) async -> Int {
        let count = await playbackController.addToQueue(tracks)
        PlaybackFeedbackPresenter.presentAddToQueueSuccess(count: count, tracks: tracks)
        return count
    }
}
