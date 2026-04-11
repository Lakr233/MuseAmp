//
//  PlaylistViewController+Table.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import AmMusicDatabaseKit
import UIKit

// MARK: - UITableViewDelegate

extension PlaylistViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }

        if isEditing {
            updateNavigationItems()
            return
        }

        tableView.deselectRow(at: indexPath, animated: true)

        switch item {
        case let .playlist(id), let .searchResult(id):
            openPlaylistDetail(for: id)
        }
    }

    func tableView(_: UITableView, didDeselectRowAt _: IndexPath) {
        guard isEditing else { return }
        updateNavigationItems()
    }

    func tableView(_: UITableView, shouldBeginMultipleSelectionInteractionAt _: IndexPath) -> Bool {
        !isSearchActive
    }

    func tableView(_: UITableView, didBeginMultipleSelectionInteractionAt _: IndexPath) {
        setEditing(true, animated: true)
    }

    func tableViewDidEndMultipleSelectionInteraction(_: UITableView) {
        updateNavigationItems()
    }

    func tableView(
        _: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath,
    ) -> UISwipeActionsConfiguration? {
        guard !isEditing, !isSearchActive,
              let item = dataSource.itemIdentifier(for: indexPath),
              case let .playlist(id) = item,
              let playlist = playlistsByID[id]
        else { return nil }

        let delete = UIContextualAction(style: .destructive, title: String(localized: "Delete")) { [weak self] _, _, completion in
            self?.presentDeleteAlert(for: [playlist]) { [weak self] in
                self?.store.deletePlaylist(id: playlist.id)
                self?.reloadPlaylists()
            }
            completion(true)
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }

    func tableView(
        _: UITableView,
        contextMenuConfigurationForRowAt indexPath: IndexPath,
        point _: CGPoint,
    ) -> UIContextMenuConfiguration? {
        guard !isEditing,
              let item = dataSource.itemIdentifier(for: indexPath)
        else { return nil }

        let id: UUID = switch item {
        case let .playlist(uuid), let .searchResult(uuid):
            uuid
        }

        guard playlistsByID[id] != nil else { return nil }

        return UIContextMenuConfiguration(
            identifier: id.uuidString as NSString,
            previewProvider: { [weak self] in
                self?.makePlaylistDetailViewController(for: id)
            },
        ) { [weak self] _ in
            self?.contextMenu(for: id)
        }
    }

    func tableView(
        _: UITableView,
        previewForHighlightingContextMenuWithConfiguration configuration: UIContextMenuConfiguration,
    ) -> UITargetedPreview? {
        targetedPreview(for: configuration)
    }

    func tableView(
        _: UITableView,
        previewForDismissingContextMenuWithConfiguration configuration: UIContextMenuConfiguration,
    ) -> UITargetedPreview? {
        targetedPreview(for: configuration)
    }

    func tableView(
        _: UITableView,
        willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration,
        animator: any UIContextMenuInteractionCommitAnimating,
    ) {
        animator.addCompletion { [weak self] in
            if let detailViewController = animator.previewViewController as? PlaylistDetailViewController {
                self?.navigationController?.pushViewController(detailViewController, animated: true)
                return
            }
            guard let playlist = self?.playlist(with: configuration.identifier) else { return }
            self?.openPlaylistDetail(for: playlist.id)
        }
    }
}

// MARK: - Navigation & Preview Helpers

extension PlaylistViewController {
    func playlist(with identifier: NSCopying?) -> Playlist? {
        guard let identifier = identifier as? NSString,
              let playlistID = UUID(uuidString: identifier as String)
        else { return nil }
        return store.playlist(for: playlistID)
    }

    func openPlaylistDetail(for playlistID: UUID) {
        let detailVC = if let environment {
            PlaylistDetailViewController(playlistID: playlistID, environment: environment)
        } else {
            PlaylistDetailViewController(playlistID: playlistID, store: store)
        }
        navigationController?.pushViewController(detailVC, animated: true)
    }

    func makePlaylistDetailViewController(for playlistID: UUID) -> PlaylistDetailViewController {
        if let environment {
            return PlaylistDetailViewController(playlistID: playlistID, environment: environment)
        }
        return PlaylistDetailViewController(playlistID: playlistID, store: store)
    }

    func contextMenu(for playlistID: UUID) -> UIMenu? {
        playlistMenuProvider.menu(
            playlistProvider: { [weak self] in
                self?.store.playlist(for: playlistID)
            },
            onOpen: { [weak self] playlist in
                self?.openPlaylistDetail(for: playlist.id)
            },
            onRename: { [weak self] _ in
                self?.reloadPlaylists()
            },
            onDuplicate: { [weak self] _ in
                self?.reloadPlaylists()
            },
            onDelete: { [weak self] _ in
                self?.reloadPlaylists()
            },
        )
    }

    func targetedPreview(for configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        guard let playlist = playlist(with: configuration.identifier),
              let row = sortedPlaylists.firstIndex(where: { $0.id == playlist.id })
        else { return nil }

        let indexPath = IndexPath(row: row, section: 0)
        guard let cell = tableView.cellForRow(at: indexPath) else { return nil }

        let parameters = UIPreviewParameters()
        parameters.backgroundColor = .secondarySystemBackground
        parameters.visiblePath = UIBezierPath(roundedRect: cell.bounds, cornerRadius: 14)
        return UITargetedPreview(view: cell, parameters: parameters)
    }
}

// MARK: - Subtitle Helpers

extension PlaylistViewController {
    func playlistSubtitle(for playlist: Playlist) -> String {
        var parts: [String] = []

        let artists = uniqueArtistNames(for: playlist)
        if let artistSummary = playlistArtistSummary(from: artists) {
            parts.append(artistSummary)
        }

        let songCount = playlist.songs.count
        parts.append(songCount == 1 ? String(localized: "1 song") : String(localized: "\(songCount) songs"))

        if let durationSummary = playlistDurationSummary(for: playlist) {
            parts.append(durationSummary)
        }

        return parts.joined(separator: " · ")
    }

    func uniqueArtistNames(for playlist: Playlist) -> [String] {
        var seen = Set<String>()
        return playlist.songs.compactMap { song in
            let name = song.artistName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            let key = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard seen.insert(key).inserted else { return nil }
            return name
        }
    }

    func playlistArtistSummary(from artists: [String]) -> String? {
        switch artists.count {
        case 0:
            return nil
        case 1:
            return artists[0]
        case 2:
            return artists.joined(separator: ", ")
        default:
            let preview = artists.prefix(2).joined(separator: ", ")
            return String(localized: "\(preview) + \(artists.count - 2) artists")
        }
    }

    func playlistDurationSummary(for playlist: Playlist) -> String? {
        let totalSeconds = playlist.songs.compactMap(\.durationMillis).reduce(0, +) / 1000
        guard totalSeconds > 0 else { return nil }

        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60

        if hours > 0, minutes > 0 {
            return String(localized: "\(hours) hr \(minutes) min")
        }
        if hours > 0 {
            return String(localized: "\(hours) hr")
        }
        return String(localized: "\(max(minutes, 1)) min")
    }
}
