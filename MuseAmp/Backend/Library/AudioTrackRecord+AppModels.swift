//
//  AudioTrackRecord+AppModels.swift
//  MuseAmp
//
//  Created by @Lakr233 on 2026/04/11.
//

import Foundation
import MuseAmpDatabaseKit
import SubsonicClientKit

nonisolated extension AudioTrackRecord {
    var playlistEntry: PlaylistEntry {
        PlaylistEntry(
            trackID: trackID,
            title: title,
            artistName: artistName,
            albumID: albumID,
            albumTitle: albumTitle,
            durationMillis: durationSeconds > 0 ? Int((durationSeconds * 1000).rounded()) : nil,
            trackNumber: trackNumber,
        )
    }

    func catalogSong(artwork: Artwork? = nil) -> CatalogSong {
        let attributes = CatalogSongAttributes(
            name: title,
            artistName: artistName,
            albumName: albumTitle.nilIfEmpty,
            durationInMillis: durationSeconds > 0 ? Int((durationSeconds * 1000).rounded()) : nil,
            trackNumber: trackNumber,
            discNumber: discNumber,
            releaseDate: releaseDate,
            composerName: composerName,
            hasLyrics: hasEmbeddedLyrics,
            artwork: artwork,
        )
        return CatalogSong(
            id: trackID,
            type: "songs",
            href: nil,
            attributes: attributes,
            relationships: nil,
        )
    }

    func playbackTrack(paths: LibraryPaths) -> PlaybackTrack {
        let artworkFileURL = paths.artworkCacheURL(for: trackID)
        let artworkURL = FileManager.default.fileExists(atPath: artworkFileURL.path) ? artworkFileURL : nil
        return PlaybackTrack(
            id: trackID,
            title: title,
            artistName: artistName,
            albumName: albumTitle.nilIfEmpty,
            albumID: albumID,
            artworkURL: artworkURL,
            durationInSeconds: durationSeconds > 0 ? durationSeconds : nil,
            localFileURL: paths.absoluteAudioURL(for: relativePath),
        )
    }

    func exportItem(
        paths: LibraryPaths,
        displayArtist: String? = nil,
        displayTitle: String? = nil,
        displayAlbumName: String? = nil,
        artworkURL: URL? = nil,
    ) -> SongExportItem {
        SongExportItem(
            sourceURL: paths.absoluteAudioURL(for: relativePath),
            artistName: displayArtist ?? artistName,
            title: displayTitle ?? title,
            trackID: trackID,
            albumID: albumID,
            albumName: displayAlbumName ?? albumTitle,
            artworkURL: artworkURL,
            albumArtistName: albumArtistName,
            trackNumber: trackNumber,
            discNumber: discNumber,
            genreName: genreName,
            composerName: composerName,
            releaseDate: releaseDate,
        )
    }

    var importedTrackMetadata: ImportedTrackMetadata {
        ImportedTrackMetadata(
            trackID: trackID,
            albumID: albumID,
            title: title,
            artistName: artistName,
            albumTitle: albumTitle,
            albumArtistName: albumArtistName,
            durationSeconds: durationSeconds,
            trackNumber: trackNumber,
            discNumber: discNumber,
            genreName: genreName,
            composerName: composerName,
            releaseDate: releaseDate,
            lyrics: nil,
            sourceKind: sourceKind,
        )
    }
}
