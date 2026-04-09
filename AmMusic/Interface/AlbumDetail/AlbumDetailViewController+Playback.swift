import UIKit

// MARK: - Playback Actions

extension AlbumDetailViewController {
    func albumPlaybackTracks() -> [PlaybackTrack] {
        tracks.map { $0.playbackTrack(apiClient: apiClient) }
    }

    func downloadedAlbumPlaybackTracks() -> [PlaybackTrack] {
        tracks.compactMap { track in
            guard environment.downloadStore.isDownloaded(trackID: track.id) else {
                return nil
            }
            return track.playbackTrack(apiClient: apiClient)
        }
    }

    func downloadedPlaybackTrack(for track: CatalogSong) -> PlaybackTrack? {
        guard environment.downloadStore.isDownloaded(trackID: track.id) else {
            return nil
        }
        return track.playbackTrack(apiClient: apiClient)
    }

    func playAlbum(shuffle: Bool = false) {
        guard ensureAlbumReadyForPlayback() else { return }
        let playbackTracks = downloadedAlbumPlaybackTracks()
        playTracks(playbackTracks, shuffle: shuffle)
    }

    func playAlbumStarting(with track: PlaybackTrack) {
        let playbackTracks = downloadedAlbumPlaybackTracks()
        guard !playbackTracks.isEmpty,
              let startIndex = playbackTracks.firstIndex(of: track)
        else {
            PlaybackFeedbackPresenter.presentFailure(title: String(localized: "Play"))
            return
        }
        playTracks(playbackTracks, startIndex: startIndex)
    }

    func playTracks(
        _ playbackTracks: [PlaybackTrack],
        startIndex: Int? = nil,
        shuffle: Bool = false
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let didPlay = if let startIndex {
                await environment.playbackController.play(
                    tracks: playbackTracks,
                    startAt: startIndex,
                    source: .album(id: album.id)
                )
            } else {
                await environment.playbackController.play(
                    tracks: playbackTracks,
                    source: .album(id: album.id),
                    shuffle: shuffle
                )
            }
            if didPlay {
                if let startIndex {
                    PlaybackFeedbackPresenter.presentPlaySuccess(tracks: playbackTracks, startIndex: startIndex)
                } else {
                    PlaybackFeedbackPresenter.presentPlaySuccess(tracks: playbackTracks, shuffle: shuffle)
                }
            } else {
                let title = shuffle ? String(localized: "Shuffle Play") : String(localized: "Play")
                PlaybackFeedbackPresenter.presentFailure(title: title)
            }
        }
    }

    func queueDownloadedAlbumTracks(playNext: Bool) {
        let playbackTracks = downloadedAlbumPlaybackTracks()
        guard !playbackTracks.isEmpty else {
            presentDownloadAllTracksAlert()
            return
        }
        enqueueTracks(playbackTracks, playNext: playNext)
    }

    func queueTrack(_ track: PlaybackTrack, playNext: Bool) {
        enqueueTracks([track], playNext: playNext)
    }

    func enqueueTracks(_ tracks: [PlaybackTrack], playNext: Bool) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let count = if playNext {
                await environment.playbackController.playNext(tracks)
            } else {
                await environment.playbackController.addToQueue(tracks)
            }
            presentQueueFeedback(count: count, tracks: tracks, playNext: playNext)
        }
    }

    func presentQueueFeedback(count: Int, tracks: [PlaybackTrack], playNext: Bool) {
        if playNext {
            PlaybackFeedbackPresenter.presentPlayNextSuccess(count: count, tracks: tracks)
        } else {
            PlaybackFeedbackPresenter.presentAddToQueueSuccess(count: count, tracks: tracks)
        }
    }

    func ensureAlbumReadyForPlayback() -> Bool {
        guard areAllTracksDownloaded else {
            presentDownloadAllTracksAlert()
            return false
        }
        return true
    }

    func presentDownloadAllTracksAlert() {
        let missingCount = max(tracks.count - downloadedTrackCount, 0)
        AppLog.info(self, "presentDownloadAllTracksAlert albumID=\(album.id) missingCount=\(missingCount)")
        let message = if missingCount > 0 {
            String(localized: "This album still has \(missingCount) songs that are not downloaded. Download all songs before playing.")
        } else {
            String(localized: "Download all songs before playing this album.")
        }

        ConfirmationAlertPresenter.present(
            on: self,
            title: String(localized: "Download All Songs"),
            message: message,
            confirmTitle: String(localized: "Download All")
        ) { [weak self] in
            self?.saveToLibrary()
        }
    }

    func presentDownloadTrackAlert(for track: CatalogSong) {
        let isDownloaded = environment.downloadStore.isDownloaded(trackID: track.id)
        AppLog.info(self, "presentDownloadTrackAlert trackID=\(track.id) isDownloaded=\(isDownloaded)")
        ConfirmationAlertPresenter.present(
            on: self,
            title: String(localized: "Download"),
            message: String(localized: "Download this song before playing."),
            confirmTitle: String(localized: "Download")
        ) { [weak self] in
            self?.saveTrackToLibrary(track)
        }
    }
}
