//
//  PlaylistViewController+Search.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import AmMusicDatabaseKit
import UIKit

// MARK: - UISearchResultsUpdating

extension PlaylistViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        let query = searchController.searchBar.text ?? ""
        if query.isEmpty {
            searchTask?.cancel()
            currentQuery = ""
            searchResultsByID = [:]
            orderedSearchResultIDs = []
            applyPlaylistsSnapshot(animated: true)
        } else {
            scheduleSearch(query: query, debounce: true)
        }
    }
}

// MARK: - Search

extension PlaylistViewController {
    func scheduleSearch(query: String, debounce: Bool) {
        searchTask?.cancel()

        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            currentQuery = ""
            searchResultsByID = [:]
            orderedSearchResultIDs = []
            applyPlaylistsSnapshot(animated: true)
            return
        }

        currentQuery = query

        searchTask = Task { [weak self, playlists = store.playlists] in
            if debounce {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
            }

            let results = await Self.filterPlaylists(playlists, query: query)
            guard !Task.isCancelled else { return }

            await MainActor.run { [weak self] in
                guard let self, !Task.isCancelled else { return }
                searchResultsByID = Dictionary(uniqueKeysWithValues: results.map { ($0.playlist.id, $0) })
                orderedSearchResultIDs = results.map(\.playlist.id)
                applySearchSnapshot(animated: true)
            }
        }
    }

    static func filterPlaylists(
        _ playlists: [Playlist],
        query: String,
    ) async -> [(playlist: Playlist, matchingSongNames: [String])] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let results = playlists.compactMap { playlist -> (playlist: Playlist, matchingSongNames: [String])? in
                    let nameMatches = playlist.name.localizedCaseInsensitiveContains(query)
                    let matchingSongs = playlist.songs
                        .filter { $0.title.localizedCaseInsensitiveContains(query) }
                        .map(\.title)
                    guard nameMatches || !matchingSongs.isEmpty else { return nil }
                    return (playlist: playlist, matchingSongNames: matchingSongs)
                }
                continuation.resume(returning: results)
            }
        }
    }
}
