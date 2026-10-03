//
//  AlbumNavigationHelper.swift
//  MuseAmp
//
//  Created by @Lakr233 on 2026/04/11.
//

import MuseAmpDatabaseKit
import SubsonicClientKit
import UIKit

@MainActor
final class AlbumNavigationHelper {
    private let environment: AppEnvironment
    private weak var viewController: UIViewController?

    init(environment: AppEnvironment, viewController: UIViewController?) {
        self.environment = environment
        self.viewController = viewController
    }

    func pushAlbumDetail(album: CatalogAlbum, highlightSongs: [String] = []) {
        let vc = AlbumDetailViewController(
            album: album,
            environment: environment,
            highlightSongs: highlightSongs,
        )
        push(vc)
    }

    func pushAlbumDetail(forCatalogSong song: CatalogSong) {
        if let album = song.relationships?.albums?.data.first {
            pushAlbumDetail(album: album, highlightSongs: [song.id])
            return
        }
        pushAlbumDetail(song: song)
    }

    func pushAlbumDetail(albumID: String, albumName: String = "", artistName: String = "", highlightSongs: [String] = []) {
        guard albumID.isKnownAlbumID else { return }
        if let localAlbum = localCatalogAlbum(albumID: albumID, albumName: albumName, artistName: artistName) {
            pushAlbumDetail(album: localAlbum, highlightSongs: highlightSongs)
            return
        }
        let stub = CatalogAlbum(
            id: albumID,
            type: "albums",
            href: nil,
            attributes: CatalogAlbumAttributes(artistName: artistName, name: albumName),
            relationships: nil,
        )
        pushAlbumDetail(album: stub, highlightSongs: highlightSongs)
    }

    func pushAlbumDetail(songID: String, albumID: String?, albumName: String = "", artistName: String = "") {
        if let albumID, albumID.isKnownAlbumID,
           let localAlbum = localCatalogAlbum(albumID: albumID, albumName: albumName, artistName: artistName)
        {
            pushAlbumDetail(album: localAlbum, highlightSongs: [songID])
            return
        }
        let vc = AlbumDetailViewController(
            songID: songID,
            albumID: albumID,
            albumName: albumName,
            artistName: artistName,
            environment: environment,
        )
        push(vc)
    }

    // MARK: - Local Album Builder

    private func localCatalogAlbum(albumID: String, albumName: String, artistName: String) -> CatalogAlbum? {
        let tracks: [AudioTrackRecord]
        do {
            tracks = try environment.databaseManager.tracks(inAlbumID: albumID)
        } catch {
            return nil
        }
        guard !tracks.isEmpty else { return nil }

        let sorted = tracks.sorted { lhs, rhs in
            if lhs.discNumber != rhs.discNumber {
                return (lhs.discNumber ?? .max) < (rhs.discNumber ?? .max)
            }
            if lhs.trackNumber != rhs.trackNumber {
                return (lhs.trackNumber ?? .max) < (rhs.trackNumber ?? .max)
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }

        let paths = environment.paths
        let catalogSongs = sorted.map { track -> CatalogSong in
            let artwork: Artwork? = if track.hasEmbeddedArtwork {
                Artwork(width: 600, height: 600, url: paths.artworkCacheURL(for: track.trackID).absoluteString)
            } else {
                nil
            }
            return track.catalogSong(artwork: artwork)
        }

        let resolvedArtistName = AlbumArtistResolver.albumArtistName(for: sorted) ?? artistName

        let firstTrack = sorted[0]
        let resolvedAlbumName = albumName.nilIfEmpty ?? firstTrack.albumTitle.nilIfEmpty ?? firstTrack.title

        let artworkTrack = sorted.first(where: \.hasEmbeddedArtwork)
        let albumArtwork: Artwork? = if let artworkTrack {
            Artwork(width: 600, height: 600, url: paths.artworkCacheURL(for: artworkTrack.trackID).absoluteString)
        } else {
            nil
        }

        let attributes = CatalogAlbumAttributes(
            artistName: resolvedArtistName,
            name: resolvedAlbumName,
            trackCount: sorted.count,
            releaseDate: firstTrack.releaseDate,
            genreNames: firstTrack.genreName.map { [$0] },
            artwork: albumArtwork,
        )
        let relationships = CatalogAlbumRelationships(
            tracks: ResourceList(
                href: nil,
                next: nil,
                data: catalogSongs,
            ),
        )

        return CatalogAlbum(
            id: albumID,
            type: "albums",
            href: nil,
            attributes: attributes,
            relationships: relationships,
        )
    }

    // MARK: - Private

    private func pushAlbumDetail(song: CatalogSong) {
        let vc = AlbumDetailViewController(song: song, environment: environment)
        push(vc)
    }

    private func push(_ vc: UIViewController) {
        viewController?.navigationController?.pushViewController(vc, animated: true)
    }
}
