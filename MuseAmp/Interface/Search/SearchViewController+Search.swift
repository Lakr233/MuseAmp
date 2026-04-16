//
//  SearchViewController+Search.swift
//  MuseAmp
//
//  Created by @Lakr233 on 2026/04/11.
//

import SubsonicClientKit
import UIKit

enum SearchResult {
    case artists([CatalogArtist])
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
                Interface.transition(with: tableView, duration: 0.2) {
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
                    group.addTask { try await .artists(self.apiClient.searchArtists(query: trimmed, limit: self.mediaPageSize, offset: 0)) }
                    group.addTask { try await .songs(self.apiClient.searchSongs(query: trimmed, limit: self.songPageSize, offset: 0)) }
                    group.addTask { try await .albums(self.apiClient.searchAlbums(query: trimmed, limit: self.mediaPageSize, offset: 0)) }
                    var collected: [SearchResult] = []
                    for try await result in group {
                        collected.append(result)
                    }
                    return collected
                }
                guard !Task.isCancelled else { return }
                var newArtists: [CatalogArtist] = []; var newSongs: [CatalogSong] = []; var newAlbums: [CatalogAlbum] = []
                for result in results {
                    switch result {
                    case let .artists(artists): newArtists = artists
                    case let .songs(s): newSongs = s
                    case let .albums(a): newAlbums = a
                    }
                }
                await MainActor.run {
                    let hadPreviousResults = self.searchState.hasResults
                    self.updateInitialResults(query: trimmed, artists: newArtists, songs: newSongs, albums: newAlbums)

                    if hadPreviousResults {
                        Interface.transition(with: self.tableView, duration: 0.2) {
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
        artists: [CatalogArtist],
        songs: [CatalogSong],
        albums: [CatalogAlbum],
    ) {
        searchState.artists.items = deduplicated(artists, id: \.id, label: "artist", source: "initial")
        searchState.artists.offset = artists.count
        searchState.artists.hasMore = artists.count >= mediaPageSize
        searchState.songs.items = deduplicated(songs, id: \.id, label: "song", source: "initial")
        searchState.songs.offset = songs.count
        searchState.songs.hasMore = songs.count >= songPageSize
        searchState.albums.items = deduplicated(albums, id: \.id, label: "album", source: "initial")
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
        case let .artists(artists):
            searchState.artists.items = deduplicated(searchState.artists.items + artists, id: \.id, label: "artist", source: "pagination")
            searchState.artists.offset += artists.count
            searchState.artists.hasMore = artists.count >= mediaPageSize
        case let .songs(songs):
            searchState.songs.items = deduplicated(searchState.songs.items + songs, id: \.id, label: "song", source: "pagination")
            searchState.songs.offset += songs.count
            searchState.songs.hasMore = songs.count >= songPageSize
        case let .albums(albums):
            searchState.albums.items = deduplicated(searchState.albums.items + albums, id: \.id, label: "album", source: "pagination")
            searchState.albums.offset += albums.count
            searchState.albums.hasMore = albums.count >= mediaPageSize
        }
        searchState.loadingMore.remove(section)
    }

    func reorderSections() {
        searchState.sectionOrder = SearchSection.resultSections
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
        case .artists:
            offset = searchState.artists.offset
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
                case .artists:
                    let items = try await apiClient.searchArtists(query: query, limit: mediaPageSize, offset: offset)
                    await MainActor.run {
                        guard self.searchState.currentQuery == query else { return }
                        self.updatePaginatedResults(section: section, items: .artists(items))
                        self.applySnapshot()
                    }
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

    func deduplicated<T>(_ items: [T], id: KeyPath<T, String>, label: String, source: String) -> [T] {
        var seen = Set<String>()
        var uniqueItems: [T] = []
        uniqueItems.reserveCapacity(items.count)

        for item in items where seen.insert(item[keyPath: id]).inserted {
            uniqueItems.append(item)
        }

        let duplicateCount = items.count - uniqueItems.count
        if duplicateCount > 0 {
            AppLog.warning(self, "Dropped duplicate \(label) search results count=\(duplicateCount) source=\(source)")
        }

        return uniqueItems
    }
}
