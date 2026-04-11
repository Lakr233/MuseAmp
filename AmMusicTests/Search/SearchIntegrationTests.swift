@testable import AmMusic
import Testing
import UIKit

@Suite(.serialized)
@MainActor
struct SearchIntegrationTests {
    @Test
    func `Search screen loads with search controller`() {
        let sandbox = TestLibrarySandbox()
        let vc = SearchViewController(environment: sandbox.makeEnvironment())
        vc.loadViewIfNeeded()

        #expect(vc.navigationItem.searchController != nil)
        #expect(vc.view.accessibilityIdentifier == nil)
    }

    @Test
    func `Album detail with highlight songs loads correctly`() {
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
                genreNames: ["Pop"],
            ),
            relationships: nil,
        )
        let vc = AlbumDetailViewController(
            album: album,
            environment: sandbox.makeEnvironment(),
            highlightSongs: ["song-5"],
        )
        vc.loadViewIfNeeded()

        #expect(vc.view.accessibilityIdentifier == "detail.album")
    }

    @Test
    func `Album detail screen loads from mock catalog album`() {
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
                genreNames: ["Pop"],
            ),
            relationships: nil,
        )
        let vc = AlbumDetailViewController(album: album, environment: sandbox.makeEnvironment())
        vc.loadViewIfNeeded()

        #expect(vc.view.accessibilityIdentifier == "detail.album")
    }

    @Test
    func `Album detail with audio traits loads correctly`() {
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
                audioTraits: ["lossless", "atmos"],
            ),
            relationships: nil,
        )
        let vc = AlbumDetailViewController(album: album, environment: sandbox.makeEnvironment())
        vc.loadViewIfNeeded()

        #expect(vc.view.accessibilityIdentifier == "detail.album")
    }

    @Test
    func `Album detail with explicit content rating decodes correctly`() {
        let song = CatalogSongAttributes(
            name: "Explicit Track",
            artistName: "Artist",
            contentRating: "explicit",
        )
        #expect(song.contentRating == "explicit")

        let cleanSong = CatalogSongAttributes(
            name: "Clean Track",
            artistName: "Artist",
            contentRating: "",
        )
        #expect(cleanSong.contentRating != "explicit")
    }

    @Test
    func `Album attributes decode contentRating`() {
        let attrs = CatalogAlbumAttributes(
            artistName: "Artist",
            name: "Album",
            contentRating: "explicit",
        )
        #expect(attrs.contentRating == "explicit")
    }
}
