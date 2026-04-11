//
//  SearchViewController+Table.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import AmMusicDatabaseKit
import AmMusicKit
import UIKit

extension SearchViewController: UITableViewDelegate, UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        guard tableView === historyTableView else { return 0 }
        return 1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection _: Int) -> Int {
        guard tableView === historyTableView else { return 0 }
        return searchHistory.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "HistoryCell", for: indexPath)
        guard searchHistory.indices.contains(indexPath.row) else {
            return cell
        }
        var config = cell.defaultContentConfiguration()
        config.image = UIImage(systemName: "clock.arrow.circlepath")
        config.text = searchHistory[indexPath.row]
        config.imageProperties.tintColor = .secondaryLabel
        cell.contentConfiguration = config
        return cell
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        if tableView === historyTableView {
            guard !searchHistory.isEmpty else { return nil }
            let headerView = tableView.dequeueReusableHeaderFooterView(
                withIdentifier: SearchSectionHeaderView.reuseID,
            ) as! SearchSectionHeaderView
            headerView.configure(
                title: String(localized: "Recent"),
                accessoryTitle: String(localized: "Clear"),
            )
            headerView.setAccessoryAction(UIAction { [weak self] _ in
                self?.clearHistory()
            })
            return headerView
        }

        guard diffableDataSource.snapshot().sectionIdentifiers.indices.contains(section) else {
            return nil
        }

        let title: String
        switch diffableDataSource.snapshot().sectionIdentifiers[section] {
        case .albums:
            title = String(localized: "Albums")
        case .songs:
            title = String(localized: "Songs")
        case .loading:
            return nil
        }

        let headerView = tableView.dequeueReusableHeaderFooterView(
            withIdentifier: SearchSectionHeaderView.reuseID,
        ) as! SearchSectionHeaderView
        headerView.configure(title: title)
        return headerView
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        if tableView === historyTableView {
            guard searchHistory.indices.contains(indexPath.row) else {
                return
            }
            let query = searchHistory[indexPath.row]
            searchController.searchBar.text = query
            searchController.isActive = true
            performSearch(query: query)
            updateHistoryVisibility()
            return
        }

        guard let item = diffableDataSource.itemIdentifier(for: indexPath) else { return }
        switch item {
        case .loadingIndicator:
            break
        case let .showMore(section):
            loadMore(section: section)
        case let .album(id):
            guard let album = searchState.albums.items.first(where: { $0.id == id }) else { return }
            navigationController?.pushViewController(AlbumDetailViewController(album: album, environment: environment), animated: true)
        case let .song(id):
            guard let song = searchState.songs.items.first(where: { $0.id == id }) else { return }
            openAlbumForSong(song)
        }
    }

    func tableView(
        _ tableView: UITableView,
        contextMenuConfigurationForRowAt indexPath: IndexPath,
        point _: CGPoint,
    ) -> UIContextMenuConfiguration? {
        guard tableView === self.tableView,
              let item = diffableDataSource.itemIdentifier(for: indexPath),
              case let .song(id) = item,
              let song = searchState.songs.items.first(where: { $0.id == id })
        else {
            return nil
        }
        return UIContextMenuConfiguration(identifier: indexPath as NSIndexPath, previewProvider: nil) { [weak self] _ in
            self?.buildSongMenu(for: song)
        }
    }

    func tableView(
        _ tableView: UITableView,
        previewForHighlightingContextMenuWithConfiguration configuration: UIContextMenuConfiguration,
    ) -> UITargetedPreview? {
        guard tableView === self.tableView else { return nil }
        return CellContextMenuPreviewHelper.targetedPreview(for: configuration, in: tableView)
    }

    func tableView(
        _ tableView: UITableView,
        previewForDismissingContextMenuWithConfiguration configuration: UIContextMenuConfiguration,
    ) -> UITargetedPreview? {
        guard tableView === self.tableView else { return nil }
        return CellContextMenuPreviewHelper.targetedPreview(for: configuration, in: tableView)
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard tableView === historyTableView else { return nil }
        let delete = UIContextualAction(style: .destructive, title: String(localized: "Delete")) { [weak self] _, _, completion in
            guard let self else { return completion(false) }
            searchHistory.remove(at: indexPath.row)
            historyStore.save(searchHistory)
            historyTableView.deleteRows(at: [indexPath], with: .automatic)
            completion(true)
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }
}

extension SearchViewController {
    func buildSongMenu(for song: CatalogSong) -> UIMenu {
        let entry = song.playlistEntry()
        return songContextMenuProvider.menu(
            for: entry,
            context: .search,
            configuration: .init(
                availablePlaylists: { [weak self] in self?.environment.playlistStore.playlists ?? [] },
                showInAlbum: { [weak self] in
                    self?.openAlbumForSong(song)
                },
                primaryActions: playbackMenuProvider.songPrimaryActions(
                    trackProvider: { [weak self] in
                        guard let self else { return nil }
                        return song.playbackTrack(apiClient: apiClient)
                    },
                    queueProvider: { [weak self] in
                        self?.searchPlaybackTracks() ?? []
                    },
                    sourceProvider: { [weak self] in
                        .search(query: self?.searchState.currentQuery.nilIfEmpty)
                    },
                ),
            ),
        ) ?? UIMenu()
    }

    func openAlbumForSong(_ song: CatalogSong) {
        albumNavigationHelper.pushAlbumDetail(forCatalogSong: song)
    }

    func searchPlaybackTracks() -> [PlaybackTrack] {
        searchState.songs.items.map { $0.playbackTrack(apiClient: apiClient) }
    }

    func loadHistory() {
        searchHistory = historyStore.load()
        updateHistoryVisibility()
    }

    func saveQuery(_ query: String) {
        searchHistory = historyStore.record(query, in: searchHistory)
        historyTableView.reloadData()
    }

    func clearHistory() {
        searchHistory.removeAll()
        historyStore.clear()
        historyTableView.reloadData()
        updateHistoryVisibility()
    }

    func updateHistoryVisibility() {
        let hasQuery = !(searchController.searchBar.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        historyTableView.isHidden = hasQuery
        tableView.isHidden = !hasQuery
    }
}
