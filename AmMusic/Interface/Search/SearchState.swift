import AmMusicKit
import Foundation

struct SearchPage<Item> {
    var items: [Item] = []
    var offset = 0
    var hasMore = false

    mutating func reset() {
        items = []
        offset = 0
        hasMore = false
    }
}

struct SearchResultsState {
    var songs = SearchPage<CatalogSong>()
    var albums = SearchPage<CatalogAlbum>()
    var loadingMore: Set<SearchSection> = []
    var sectionOrder: [SearchSection] = SearchSection.resultSections
    var currentQuery = ""
    var isSearching = false
    var searchError: String?

    var hasResults: Bool {
        !songs.items.isEmpty || !albums.items.isEmpty
    }

    mutating func reset() {
        songs.reset()
        albums.reset()
        loadingMore = []
        sectionOrder = SearchSection.resultSections
        currentQuery = ""
        isSearching = false
        searchError = nil
    }
}

struct SearchHistoryStore {
    private let defaults: UserDefaults
    private let key: String
    private let limit: Int

    init(
        defaults: UserDefaults = .standard,
        key: String = "SearchHistory",
        limit: Int = 20
    ) {
        self.defaults = defaults
        self.key = key
        self.limit = limit
    }

    func load() -> [String] {
        defaults.stringArray(forKey: key) ?? []
    }

    func save(_ history: [String]) {
        defaults.set(history, forKey: key)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }

    func record(_ query: String, in currentHistory: [String]) -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return currentHistory }

        var updatedHistory = currentHistory
        updatedHistory.removeAll { $0 == trimmed }
        updatedHistory.insert(trimmed, at: 0)
        if updatedHistory.count > limit {
            updatedHistory = Array(updatedHistory.prefix(limit))
        }
        save(updatedHistory)
        return updatedHistory
    }
}
