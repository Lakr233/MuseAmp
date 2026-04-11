//
//  AlbumDetailViewController+Table.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import AmMusicPlayerKit
import UIKit

// MARK: - UITableViewDelegate

extension AlbumDetailViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let item = dataSource.itemIdentifier(for: indexPath),
              case let .track(position, _, _) = item
        else { return }
        if let cell = tableView.cellForRow(at: indexPath) as? AlbumTrackCell {
            cell.animateTapHighlight()
        }
        playTrack(at: position)
    }

    func tableView(_: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return false }
        if case .track = item { return true }
        return false
    }

    func tableView(
        _: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath,
    ) -> UISwipeActionsConfiguration? {
        guard let item = dataSource.itemIdentifier(for: indexPath),
              case let .track(_, id, _) = item,
              let track = tracksByID[id],
              environment.downloadStore.isDownloaded(trackID: id)
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
              case let .track(_, id, _) = item,
              let track = tracksByID[id]
        else {
            return nil
        }
        return UIContextMenuConfiguration(identifier: indexPath as NSIndexPath, previewProvider: nil) { [weak self] _ in
            self?.buildTrackMenu(for: track)
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

    func playTrack(at index: Int) {
        guard tracks.indices.contains(index) else {
            return
        }
        let track = tracks[index]
        guard let playbackTrack = downloadedPlaybackTrack(for: track) else {
            presentDownloadTrackAlert(for: track)
            return
        }
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
        } else {
            playAlbumStarting(with: playbackTrack)
        }
    }
}
