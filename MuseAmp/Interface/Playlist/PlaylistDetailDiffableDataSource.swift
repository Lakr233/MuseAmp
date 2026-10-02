//
//  PlaylistDetailDiffableDataSource.swift
//  MuseAmp
//
//  Created by @Lakr233 on 2026/04/11.
//

import MuseAmpDatabaseKit
import UIKit

// MARK: - PlaylistDetailDiffableDataSource

@MainActor
final class PlaylistDetailDiffableDataSource: UITableViewDiffableDataSource<PlaylistDetailSection, PlaylistDetailItem> {
    let playlistID: UUID
    let store: PlaylistStore

    init(
        tableView: UITableView,
        playlistID: UUID,
        store: PlaylistStore,
        cellProvider: @escaping UITableViewDiffableDataSource<PlaylistDetailSection, PlaylistDetailItem>.CellProvider,
    ) {
        self.playlistID = playlistID
        self.store = store
        super.init(tableView: tableView, cellProvider: cellProvider)
    }

    override func tableView(_: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        guard let item = itemIdentifier(for: indexPath) else { return false }
        if case .song = item {
            return true
        }
        return false
    }

    override func tableView(_: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        guard let item = itemIdentifier(for: indexPath) else { return false }
        if case .song = item {
            return true
        }
        return false
    }

    override func tableView(
        _: UITableView,
        moveRowAt sourceIndexPath: IndexPath,
        to destinationIndexPath: IndexPath,
    ) {
        guard let sourceItem = itemIdentifier(for: sourceIndexPath),
              case .song = sourceItem
        else { return }

        let tracksSnapshot = snapshot().itemIdentifiers(inSection: .tracks)
        guard let sourceTrackIndex = tracksSnapshot.firstIndex(of: sourceItem) else { return }

        let destTrackIndex: Int = if let destItem = itemIdentifier(for: destinationIndexPath),
                                     let idx = tracksSnapshot.firstIndex(of: destItem)
        {
            idx
        } else {
            max(tracksSnapshot.count - 1, 0)
        }

        AppLog.info("PlaylistDetailViewController", "moveSong from=\(sourceTrackIndex) to=\(destTrackIndex) playlistID=\(playlistID)")
        store.moveSong(in: playlistID, from: sourceTrackIndex, to: destTrackIndex)
    }

    override func tableView(
        _: UITableView,
        commit editingStyle: UITableViewCell.EditingStyle,
        forRowAt indexPath: IndexPath,
    ) {
        guard editingStyle == .delete,
              let item = itemIdentifier(for: indexPath),
              case let .song(entryID, _) = item,
              let songs = store.playlist(for: playlistID)?.songs,
              let songIndex = songs.firstIndex(where: { $0.entryID == entryID })
        else { return }

        let song = songs[songIndex]
        AppLog.info("PlaylistDetailViewController", "removeSong index=\(songIndex) trackID=\(song.trackID) name=\(song.title) from playlistID=\(playlistID)")
        store.removeSong(at: songIndex, from: playlistID)

        var snapshot = snapshot()
        snapshot.deleteItems([item])
        apply(snapshot, animatingDifferences: true)
    }
}
