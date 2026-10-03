//
//  PlaylistDetailViewController+Table.swift
//  MuseAmp
//
//  Created by @Lakr233 on 2026/04/11.
//

import MuseAmpDatabaseKit
import UIKit

// MARK: - UITableViewDelegate

extension PlaylistDetailViewController {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard environment != nil,
              let item = dataSource.itemIdentifier(for: indexPath),
              case let .song(entryID, _) = item,
              let songs = playlist?.songs,
              let songIndex = songs.firstIndex(where: { $0.entryID == entryID })
        else { return }
        playSong(at: songIndex)
    }

    func tableView(_: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return false }
        if case .song = item {
            return true
        }
        return false
    }

    func tableView(
        _: UITableView,
        contextMenuConfigurationForRowAt indexPath: IndexPath,
        point _: CGPoint,
    ) -> UIContextMenuConfiguration? {
        guard let item = dataSource.itemIdentifier(for: indexPath),
              case let .song(entryID, _) = item,
              let songs = playlist?.songs,
              let song = songs.first(where: { $0.entryID == entryID })
        else { return nil }

        return UIContextMenuConfiguration(identifier: indexPath as NSIndexPath, previewProvider: nil) { [weak self] _ in
            guard let self else { return nil }
            let removeAction = UIAction(
                title: String(localized: "Move Out"),
                image: UIImage(systemName: "minus.circle"),
            ) { [weak self] _ in
                self?.confirmRemove(song: song)
            }

            var destructiveActions: [UIMenuElement] = [removeAction]
            if environment != nil {
                destructiveActions.append(UIAction(
                    title: String(localized: "Delete Song"),
                    image: UIImage(systemName: "trash"),
                    attributes: .destructive,
                ) { [weak self] _ in
                    self?.confirmDeleteSong(song)
                })
            }
            var repairAction: UIAction?
            if let environment,
               let track = environment.libraryDatabase.trackOrNil(byID: song.trackID),
               track.trackID.isCatalogID || track.albumID.isCatalogID
            {
                repairAction = TrackArtworkRepairPresenter.makeMenuAction { [weak self] _ in
                    guard let self else { return }
                    TrackArtworkRepairPresenter.present(
                        on: self,
                        track: track,
                        repairService: environment.trackArtworkRepairService,
                    )
                }
            }

            return songContextMenuProvider.menu(
                title: song.title,
                for: song,
                context: .playlist,
                configuration: .init(
                    availablePlaylists: { [weak self] in self?.availableTargetPlaylists(for: song) ?? [] },
                    showInAlbum: environment == nil ? nil : { [weak self] in
                        self?.openAlbum(for: song)
                    },
                    exportItems: { [weak self] in
                        guard let item = self?.exportItem(for: song) else { return [] }
                        return [item]
                    },
                    primaryActions: playbackMenuProvider?.songPrimaryActions(
                        trackProvider: { [weak self] in
                            self?.playbackTrack(for: song)
                        },
                        queueProvider: { [weak self] in
                            self?.playlistPlaybackTracks() ?? []
                        },
                        sourceProvider: { [weak self] in
                            .playlist(self?.playlistID ?? UUID())
                        },
                    ) ?? [],
                    secondaryActions: repairAction.map { [$0] } ?? [],
                    destructiveActions: destructiveActions,
                ),
            )
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

    func tableView(
        _: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath,
    ) -> UISwipeActionsConfiguration? {
        guard let item = dataSource.itemIdentifier(for: indexPath),
              case let .song(entryID, _) = item,
              let song = playlist?.songs.first(where: { $0.entryID == entryID })
        else { return nil }

        let moveOutAction = UIContextualAction(
            style: .destructive,
            title: String(localized: "Move Out"),
        ) { [weak self] _, _, completion in
            self?.confirmRemove(song: song)
            completion(true)
        }

        let configuration = UISwipeActionsConfiguration(actions: [moveOutAction])
        configuration.performsFirstActionWithFullSwipe = false
        return configuration
    }

    func tableView(
        _: UITableView,
        targetIndexPathForMoveFromRowAt sourceIndexPath: IndexPath,
        toProposedIndexPath proposedDestinationIndexPath: IndexPath,
    ) -> IndexPath {
        guard let tracksSection = dataSource.snapshot().indexOfSection(.tracks) else {
            return sourceIndexPath
        }
        if proposedDestinationIndexPath.section < tracksSection {
            return IndexPath(row: 0, section: tracksSection)
        }
        if proposedDestinationIndexPath.section > tracksSection {
            let trackCount = dataSource.snapshot().numberOfItems(inSection: .tracks)
            return IndexPath(row: max(trackCount - 1, 0), section: tracksSection)
        }
        return proposedDestinationIndexPath
    }
}

// MARK: - UITableViewDragDelegate

extension PlaylistDetailViewController {
    func tableView(_: UITableView, itemsForBeginning _: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
        guard let item = dataSource.itemIdentifier(for: indexPath),
              case let .song(entryID, _) = item,
              let songs = playlist?.songs,
              let song = songs.first(where: { $0.entryID == entryID }),
              let exportItem = exportItem(for: song)
        else { return [] }

        let fileExtension = exportItem.sourceURL.pathExtension
        let fileName = fileExtension.isEmpty
            ? exportItem.preferredFileBaseName
            : "\(exportItem.preferredFileBaseName).\(fileExtension)"

        let provider = NSItemProvider()
        provider.suggestedName = fileName
        provider.registerFileRepresentation(
            forTypeIdentifier: "public.audio",
            fileOptions: [],
            visibility: .all,
        ) { completion in
            completion(exportItem.sourceURL, false, nil)
            return nil
        }

        let dragItem = UIDragItem(itemProvider: provider)
        dragItem.localObject = song
        return [dragItem]
    }
}
