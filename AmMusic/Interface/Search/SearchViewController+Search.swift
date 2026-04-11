//
//  SearchViewController+Search.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import AmMusicKit
import UIKit

enum SearchResult {
    case songs([CatalogSong])
    case albums([CatalogAlbum])
}

extension SearchViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        debounceTask?.cancel()
        let query = searchController.searchBar.text ?? ""
        updateHistoryVisibility()
        debounceTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 300_000_000) } catch { return }
            self?.performSearch(query: query)
        }
    }
}

extension SearchViewController {
    func performSearch(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchTask?.cancel()
            let hadResults = resetSearchState()
            if hadResults {
                InterfaceAnimate.transition(with: tableView, duration: 0.2) {
                    self.applySnapshot(animating: false)
                }
            } else {
                applySnapshot(animating: false)
            }
            updateHistoryVisibility(); return
        }
        guard trimmed != searchState.currentQuery || (!searchState.hasResults && !searchState.isSearching) else {
            return
        }
        searchTask?.cancel()
        searchState.reset()
        searchState.currentQuery = trimmed
        searchState.isSearching = true
        applySnapshot(animating: false)
        searchTask = Task { [weak self] in
            guard let self else { return }
            do {
                let results = try await withThrowingTaskGroup(of: SearchResult.self) { group in
                    group.addTask { try await .songs(self.apiClient.searchSongs(query: trimmed, limit: self.songPageSize, offset: 0)) }
                    group.addTask { try await .albums(self.apiClient.searchAlbums(query: trimmed, limit: self.mediaPageSize, offset: 0)) }
                    var collected: [SearchResult] = []
                    for try await result in group {
                        collected.append(result)
                    }
                    return collected
                }
                guard !Task.isCancelled else { return }
                var newSongs: [CatalogSong] = []; var newAlbums: [CatalogAlbum] = []
                for result in results {
                    switch result {
                    case let .songs(s): newSongs = s
                    case let .albums(a): newAlbums = a
                    }
                }
                await MainActor.run {
                    let hadPreviousResults = self.searchState.hasResults
                    self.updateInitialResults(query: trimmed, songs: newSongs, albums: newAlbums)

                    if hadPreviousResults {
                        InterfaceAnimate.transition(with: self.tableView, duration: 0.2) {
                            self.applySnapshot(animating: false)
                        }
                    } else {
                        self.applySnapshot(animating: false)
                    }
                    self.saveQuery(trimmed)
                }
            } catch {
                if !Task.isCancelled {
                    await MainActor.run {
                        self.searchState.isSearching = false
                        self.searchState.searchError = error.localizedDescription
                        self.applySnapshot(animating: false)
                    }
                    AppLog.error(self, "Search failed: \(error.localizedDescription)")
                }
            }
        }
    }

    func resetSearchState() -> Bool {
        let hadResults = searchState.hasResults
        searchState.reset()
        return hadResults
    }

    func updateInitialResults(
        query: String,
        songs: [CatalogSong],
        albums: [CatalogAlbum],
    ) {
        searchState.songs.items = deduplicated(songs, label: "song", source: "initial")
        searchState.songs.offset = songs.count
        searchState.songs.hasMore = songs.count >= songPageSize
        searchState.albums.items = deduplicated(albums, label: "album", source: "initial")
        searchState.albums.offset = albums.count
        searchState.albums.hasMore = albums.count >= mediaPageSize
        searchState.currentQuery = query
        searchState.isSearching = false
        searchState.searchError = nil
        searchState.loadingMore = []
        reorderSections()
    }

    func updatePaginatedResults(section: SearchSection, items: SearchResult) {
        switch items {
        case let .songs(songs):
            searchState.songs.items = deduplicated(searchState.songs.items + songs, label: "song", source: "pagination")
            searchState.songs.offset += songs.count
            searchState.songs.hasMore = songs.count >= songPageSize
        case let .albums(albums):
            searchState.albums.items = deduplicated(searchState.albums.items + albums, label: "album", source: "pagination")
            searchState.albums.offset += albums.count
            searchState.albums.hasMore = albums.count >= mediaPageSize
        }
        searchState.loadingMore.remove(section)
    }

    func reorderSections() {
        let query = searchState.currentQuery.lowercased()
        func score(names: [String]) -> Int {
            var best = 0
            for n in names {
                let l = n.lowercased(); if l == query { return 3 }; if l.hasPrefix(query) { best = max(best, 2) } else if l.contains(query) { best = max(best, 1) }
            }
            return best
        }
        let songScore = score(names: searchState.songs.items.map(\.attributes.name))
        let albumScore = score(names: searchState.albums.items.map(\.attributes.name))
        let tb: [SearchSection: Int] = [.songs: 0, .albums: 1, .loading: 2]
        searchState.sectionOrder = SearchSection.resultSections.sorted { a, b in
            let sa: Int; let sb: Int
            switch a { case .songs: sa = songScore; case .albums: sa = albumScore; case .loading: sa = -1 }
            switch b { case .songs: sb = songScore; case .albums: sb = albumScore; case .loading: sb = -1 }
            if sa != sb { return sa > sb }; return tb[a]! < tb[b]!
        }
    }

    func loadMore(section: SearchSection) {
        guard section != .loading else { return }
        guard !searchState.loadingMore.contains(section) else { return }
        searchState.loadingMore.insert(section)
        var snapshot = diffableDataSource.snapshot()
        snapshot.reconfigureItems([.showMore(section)])
        diffableDataSource.apply(snapshot, animatingDifferences: true)
        let query = searchState.currentQuery
        let offset: Int
        switch section {
        case .songs:
            offset = searchState.songs.offset
        case .albums:
            offset = searchState.albums.offset
        case .loading:
            return
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                switch section {
                case .songs:
                    let items = try await apiClient.searchSongs(query: query, limit: songPageSize, offset: offset)
                    await MainActor.run {
                        guard self.searchState.currentQuery == query else { return }
                        self.updatePaginatedResults(section: section, items: .songs(items))
                        self.applySnapshot()
                    }
                case .albums:
                    let items = try await apiClient.searchAlbums(query: query, limit: mediaPageSize, offset: offset)
                    await MainActor.run {
                        guard self.searchState.currentQuery == query else { return }
                        self.updatePaginatedResults(section: section, items: .albums(items))
                        self.applySnapshot()
                    }
                case .loading:
                    return
                }
            } catch {
                AppLog.error(self, "Load more failed: \(error.localizedDescription)")
                await MainActor.run {
                    self.searchState.loadingMore.remove(section)
                    self.applySnapshot()
                }
            }
        }
    }

    func deduplicated<T: Identifiable>(_ items: [T], label: String, source: String) -> [T] where T.ID == String {
        var seen = Set<String>()
        var uniqueItems: [T] = []
        uniqueItems.reserveCapacity(items.count)

        for item in items where seen.insert(item.id).inserted {
            uniqueItems.append(item)
        }

        let duplicateCount = items.count - uniqueItems.count
        if duplicateCount > 0 {
            AppLog.warning(self, "Dropped duplicate \(label) search results count=\(duplicateCount) source=\(source)")
        }

        return uniqueItems
    }
}
