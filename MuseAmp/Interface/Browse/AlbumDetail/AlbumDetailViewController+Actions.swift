//
//  AlbumDetailViewController+Actions.swift
//  MuseAmp
//
//  Created by @Lakr233 on 2026/04/11.
//

import MuseAmpDatabaseKit
import UIKit

extension AlbumDetailViewController {
    var areAllTracksDownloaded: Bool {
        guard !tracks.isEmpty else { return false }
        return tracks.allSatisfy { environment.downloadStore.isDownloaded(trackID: $0.id) }
    }

    var downloadedTrackCount: Int {
        tracks.reduce(into: 0) { count, track in
            if environment.downloadStore.isDownloaded(trackID: track.id) {
                count += 1
            }
        }
    }

    var downloadedStorageSizeBytes: Int64 {
        environment.downloadStore.storageSize(
            forTrackIDs: Set(tracks.map(\.id)),
            audioDirectory: environment.paths.audioDirectory,
        )
    }

    func saveAlbumAsPlaylist() {
        let entries = playlistEntriesForCurrentTracks()
        guard !entries.isEmpty else { return }

        let playlist = environment.playlistStore.createPlaylist(name: album.attributes.name)
        entries.forEach { environment.playlistStore.addSong($0, to: playlist.id) }
        fetchLyricsInBackground(trackIDs: tracks.map(\.id), playlistID: playlist.id)
        refreshNavBarMenu()
    }

    func playlistEntriesForCurrentTracks() -> [PlaylistEntry] {
        tracks.map { track in
            track.playlistEntry(
                albumID: album.id,
                albumName: track.attributes.albumName ?? album.attributes.name,
            )
        }
    }

    func saveToLibrary() {
        guard !tracks.isEmpty else { return }

        let requests = tracks.map { $0.downloadRequest(albumID: album.id, apiClient: environment.apiClient) }
        let result = environment.downloadManager.submitRequests(requests)
        DownloadSubmissionFeedbackPresenter.present(result)
    }

    func fetchLyricsInBackground(trackIDs: [String], playlistID: UUID) {
        guard !trackIDs.isEmpty else { return }
        Task { [weak self] in
            guard let self else { return }
            for trackID in trackIDs {
                do {
                    let lyrics = try await environment.lyricsService.fetchLyrics(for: trackID)
                    environment.playlistStore.updateLyrics(lyrics, trackID: trackID, playlistID: playlistID)
                } catch {
                    AppLog.info(self, "Lyrics unavailable for \(trackID)")
                }
            }
        }
    }

    func confirmDeleteTrack(_ track: CatalogSong) {
        ConfirmationAlertPresenter.present(
            on: self,
            title: String(localized: "Delete Song"),
            message: String(localized: "Delete \"\(track.attributes.name)\" from your saved songs? This cannot be undone."),
            confirmTitle: String(localized: "Delete Song"),
        ) { [weak self] in
            self?.deleteTrack(track)
        }
    }

    private func deleteTrack(_ track: CatalogSong) {
        environment.musicLibraryTrackRemovalService.removeTrack(trackID: track.id)
        environment.playbackController.removeTracksFromQueue(trackIDs: [track.id])

        let hasRemainingDownloads = tracks.contains { $0.id != track.id && environment.downloadStore.isDownloaded(trackID: $0.id) }
        if !hasRemainingDownloads {
            navigationController?.popViewController(animated: true)
            return
        }

        refreshDownloadStateUI()
    }

    func saveTrackToLibrary(_ track: CatalogSong) {
        let request = track.downloadRequest(albumID: album.id, apiClient: environment.apiClient)
        let result = environment.downloadManager.submitRequests([request])
        DownloadSubmissionFeedbackPresenter.present(result)
    }

    func exportItem(for track: CatalogSong) -> SongExportItem? {
        guard let localTrack = environment.libraryDatabase.trackOrNil(byID: track.id) else {
            return nil
        }

        return localTrack.exportItem(
            paths: environment.paths,
            displayArtist: track.attributes.artistName,
            displayTitle: track.attributes.name,
            displayAlbumName: track.attributes.albumName ?? album.attributes.name,
            artworkURL: track.attributes.artwork?.imageURL(width: 600, height: 600),
        )
    }
}
