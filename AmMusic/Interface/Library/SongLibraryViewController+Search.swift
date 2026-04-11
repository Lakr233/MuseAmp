//
//  SongLibraryViewController+Search.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import AmMusicDatabaseKit
import UIKit

// MARK: - UISearchResultsUpdating

extension SongLibraryViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        let query = searchController.searchBar.text ?? ""
        searchTask?.cancel()
        if query.isEmpty {
            currentQuery = ""
            filteredTracks = []
            tracksByID = [:]
            applyAlbumsSnapshot()
        } else {
            performSearch(query: query)
        }
    }
}

// MARK: - Search

extension SongLibraryViewController {
    func performSearch(query: String) {
        currentQuery = query
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            filteredTracks = []
            tracksByID = [:]
            applyAlbumsSnapshot()
            return
        }

        let db = environment.libraryDatabase
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 300_000_000) } catch { return }

            let results: [AudioTrackRecord] = await Task.detached(priority: .userInitiated) { [db] in
                do {
                    return try db.searchTracks(query: query)
                } catch {
                    AppLog.error("SongLibraryViewController", "searchTracks failed: \(error)")
                    return []
                }
            }.value

            guard !Task.isCancelled else { return }

            await MainActor.run { [weak self] in
                guard let self, currentQuery == query else { return }
                filteredTracks = results
                tracksByID = Dictionary(uniqueKeysWithValues: results.map { ($0.trackID, $0) })
                applySearchSnapshot()
            }
        }
    }
}
