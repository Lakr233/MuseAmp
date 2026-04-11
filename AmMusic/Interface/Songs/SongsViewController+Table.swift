//
//  SongsViewController+Table.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import AmMusicDatabaseKit
import AmMusicPlayerKit
import UIKit

// MARK: - UITableViewDelegate

extension SongsViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let item = dataSource.itemIdentifier(for: indexPath),
              case let .song(trackID) = item
        else { return }

        let lookup = isSearchActive ? searchTracksByID : tracksByID
        guard let track = lookup[trackID] else { return }
        Task { await playTrack(track) }
    }

    func tableView(
        _: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath,
    ) -> UISwipeActionsConfiguration? {
        guard let item = dataSource.itemIdentifier(for: indexPath),
              case let .song(trackID) = item,
              let track = tracksByID[trackID]
        else { return nil }

        let delete = UIContextualAction(style: .destructive, title: String(localized: "Delete")) { [weak self] _, _, completion in
            self?.confirmDeleteTrack(track)
            completion(true)
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }

    func tableView(
        _: UITableView,
        contextMenuConfigurationForRowAt indexPath: IndexPath,
        point _: CGPoint,
    ) -> UIContextMenuConfiguration? {
        guard let item = dataSource.itemIdentifier(for: indexPath),
              case let .song(trackID) = item
        else { return nil }

        let lookup = isSearchActive ? searchTracksByID : tracksByID
        guard let track = lookup[trackID] else { return nil }

        return UIContextMenuConfiguration(identifier: indexPath as NSIndexPath, previewProvider: nil) { [weak self] _ in
            self?.buildContextMenu(for: track)
        }
    }

    func tableView(
        _: UITableView,
        previewForHighlightingContextMenuWithConfiguration configuration: UIContextMenuConfiguration,
    ) -> UITargetedPreview? {
        CellContextMenuPreviewHelper.targetedPreview(for: configuration, in: tableView)
    }

    func tableView(
        _: UITableView,
        previewForDismissingContextMenuWithConfiguration configuration: UIContextMenuConfiguration,
    ) -> UITargetedPreview? {
        CellContextMenuPreviewHelper.targetedPreview(for: configuration, in: tableView)
    }
}

// MARK: - Playback & Navigation

extension SongsViewController {
    func playTrack(_ track: AudioTrackRecord) async {
        let playbackTrack = track.playbackTrack(paths: environment.paths)
        if environment.playbackController.latestSnapshot.state == .playing
            || environment.playbackController.latestSnapshot.state == .buffering
        {
            if playbackTrack.id == environment.playbackController.latestSnapshot.currentTrack?.id {
                environment.playbackController.seek(to: 0)
                return
            }
            let result = await environment.playbackController.playNext([playbackTrack])
            switch result {
            case .alreadyQueued:
                environment.playbackController.next()
            case .queued:
                PlaybackFeedbackPresenter.presentPlayNextResult(result, tracks: [playbackTrack])
            default:
                break
            }
        } else {
            let tracks = visiblePlaybackTracks()
            await environment.playbackController.play(
                track: playbackTrack,
                in: tracks,
                source: .library,
            )
        }
    }

    func openAlbumForTrack(_ track: AudioTrackRecord) {
        albumNavigationHelper.pushAlbumDetail(
            songID: track.trackID,
            albumID: track.albumID,
        )
    }

    func confirmDeleteTrack(_ track: AudioTrackRecord) {
        ConfirmationAlertPresenter.present(
            on: self,
            title: String(localized: "Delete Song"),
            message: String(localized: "Delete \"\(track.title)\" from your saved songs? This cannot be undone."),
            confirmTitle: String(localized: "Delete Song"),
        ) { [weak self] in
            self?.deleteTrack(track)
        }
    }

    private func deleteTrack(_ track: AudioTrackRecord) {
        environment.musicLibraryTrackRemovalService.removeTrack(trackID: track.trackID)
        environment.playbackController.removeTracksFromQueue(trackIDs: [track.trackID])
        reloadTracks()
    }

    func buildContextMenu(for track: AudioTrackRecord) -> UIMenu? {
        let entry = playlistEntryForTrack(track)

        let deleteAction = UIAction(
            title: String(localized: "Delete Song"),
            image: UIImage(systemName: "trash"),
            attributes: .destructive,
        ) { [weak self] _ in
            self?.confirmDeleteTrack(track)
        }

        return songContextMenuProvider.menu(
            title: track.title,
            for: entry,
            context: .library,
            configuration: .init(
                availablePlaylists: { [weak self] in
                    self?.environment.playlistStore.playlists ?? []
                },
                showInAlbum: { [weak self] in
                    self?.openAlbumForTrack(track)
                },
                exportItems: { [weak self] in
                    guard let self else { return [] }
                    return [exportItem(for: track)]
                },
                primaryActions: playbackMenuProvider.songPrimaryActions(
                    trackProvider: { [weak self] in
                        guard let self else { return nil }
                        return track.playbackTrack(paths: environment.paths)
                    },
                    queueProvider: { [weak self] in
                        self?.visiblePlaybackTracks() ?? []
                    },
                    sourceProvider: { .library },
                ),
                destructiveActions: [deleteAction],
            ),
        )
    }
}

// MARK: - UISearchResultsUpdating

extension SongsViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        let query = searchController.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        currentQuery = query

        if query.isEmpty {
            searchTask?.cancel()
            searchTask = nil
            filteredTracks = []
            searchTracksByID = [:]
            applySongsSnapshot()
            return
        }

        performSearch(query: query)
    }

    func performSearch(query: String) {
        searchTask?.cancel()

        searchTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }

            let db = environment.libraryDatabase
            let results: [AudioTrackRecord]
            do {
                results = try await Task.detached(priority: .userInitiated) {
                    try db.searchTracks(query: query)
                }.value
            } catch {
                AppLog.error(self, "searchTracks failed: \(error)")
                return
            }

            guard !Task.isCancelled else { return }
            filteredTracks = results
            searchTracksByID = Dictionary(uniqueKeysWithValues: results.map { ($0.trackID, $0) })
            applySearchSnapshot()
        }
    }
}
