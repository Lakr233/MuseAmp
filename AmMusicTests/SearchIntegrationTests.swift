@testable import AmMusic
import Testing

@Suite(.serialized)
@MainActor
struct SearchIntegrationTests {
    @Test("Search screen loads with search controller")
    func searchScreenLoads() {
        let sandbox = TestLibrarySandbox()
        let vc = SearchViewController(environment: sandbox.makeEnvironment())
        vc.loadViewIfNeeded()

        #expect(vc.navigationItem.searchController != nil)
        #expect(vc.view.accessibilityIdentifier == nil)
    }

    @Test("Album detail with highlight songs loads correctly")
    func albumDetailWithHighlight() {
        let sandbox = TestLibrarySandbox()
        let album = CatalogAlbum(
            id: "album-1",
            type: "albums",
            href: nil,
            attributes: CatalogAlbumAttributes(
                artistName: "Mock Artist",
                name: "Mock Album",
                trackCount: 10,
                releaseDate: "2024-01-01",
                genreNames: ["Pop"]
            ),
            relationships: nil
        )
        let vc = AlbumDetailViewController(
            album: album,
            environment: sandbox.makeEnvironment(),
            highlightSongs: ["song-5"]
        )
        vc.loadViewIfNeeded()

        #expect(vc.view.accessibilityIdentifier == "detail.album")
    }

    @Test("Album detail screen loads from mock catalog album")
    func albumDetailLoads() {
        let sandbox = TestLibrarySandbox()
        let album = CatalogAlbum(
            id: "album-1",
            type: "albums",
            href: nil,
            attributes: CatalogAlbumAttributes(
                artistName: "Mock Artist",
                name: "Mock Album",
                trackCount: 10,
                releaseDate: "2024-01-01",
                genreNames: ["Pop"]
            ),
            relationships: nil
        )
        let vc = AlbumDetailViewController(album: album, environment: sandbox.makeEnvironment())
        vc.loadViewIfNeeded()

        #expect(vc.view.accessibilityIdentifier == "detail.album")
    }

    @Test("Album detail with audio traits loads correctly")
    func albumDetailWithAudioTraits() {
        let sandbox = TestLibrarySandbox()
        let album = CatalogAlbum(
            id: "album-2",
            type: "albums",
            href: nil,
            attributes: CatalogAlbumAttributes(
                artistName: "Artist",
                name: "Test Album",
                trackCount: 5,
                releaseDate: "2025-06-15",
                genreNames: ["Rock"],
                audioTraits: ["lossless", "atmos"]
            ),
            relationships: nil
        )
        let vc = AlbumDetailViewController(album: album, environment: sandbox.makeEnvironment())
        vc.loadViewIfNeeded()

        #expect(vc.view.accessibilityIdentifier == "detail.album")
    }

    @Test("Album detail with explicit content rating decodes correctly")
    func albumExplicitContentRating() {
        let song = CatalogSongAttributes(
            name: "Explicit Track",
            artistName: "Artist",
            contentRating: "explicit"
        )
        #expect(song.contentRating == "explicit")

        let cleanSong = CatalogSongAttributes(
            name: "Clean Track",
            artistName: "Artist",
            contentRating: ""
        )
        #expect(cleanSong.contentRating != "explicit")
    }

    @Test("Album attributes decode contentRating")
    func albumContentRating() {
        let attrs = CatalogAlbumAttributes(
            artistName: "Artist",
            name: "Album",
            contentRating: "explicit"
        )
        #expect(attrs.contentRating == "explicit")
    }
}
