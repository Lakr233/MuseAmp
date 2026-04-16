//
//  ArtistDetailViewController+Playback.swift
//  MuseAmp
//
//  Created by @libr on 2026/04/16.
//

import Foundation
import MuseAmpPlayerKit

extension ArtistDetailViewController {
    func artistPlaybackTracks() -> [PlaybackTrack] {
        songs.map { $0.playbackTrack(apiClient: apiClient) }
    }

    func playSong(id: String) {
        guard let song = songsByID[id] else { return }
        let playbackTrack = song.playbackTrack(apiClient: apiClient)

        if environment.playbackController.latestSnapshot.state == .playing
            || environment.playbackController.latestSnapshot.state == .buffering
        {
            if playbackTrack.id == environment.playbackController.latestSnapshot.currentTrack?.id {
                environment.playbackController.seek(to: 0)
                return
            }

            Task { @MainActor [weak self] in
                guard let self else { return }
                let result = await environment.playbackController.playNext([playbackTrack])
                switch result {
                case .alreadyQueued:
                    environment.playbackController.next()
                case .queued:
                    PlaybackFeedbackPresenter.presentPlayNextResult(result, tracks: [playbackTrack])
                default:
                    break
                }
            }
            return
        }

        let playbackTracks = artistPlaybackTracks()
        guard let startIndex = playbackTracks.firstIndex(of: playbackTrack) else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let didPlay = await environment.playbackController.play(
                tracks: playbackTracks,
                startAt: startIndex,
                source: .adHoc(name: artist.attributes.name),
            )
            if didPlay {
                PlaybackFeedbackPresenter.presentPlaySuccess(tracks: playbackTracks, startIndex: startIndex)
            } else {
                PlaybackFeedbackPresenter.presentFailure(title: String(localized: "Play"))
            }
        }
    }
}
