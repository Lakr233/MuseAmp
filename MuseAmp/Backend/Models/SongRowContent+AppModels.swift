//
//  SongRowContent+AppModels.swift
//  MuseAmp
//
//  Created by @Lakr233 on 2026/04/11.
//

import Foundation
import MuseAmpDatabaseKit
import SubsonicClientKit

extension SongRowContent {
    init(catalogSong: CatalogSong, artworkURL: URL? = nil) {
        self.init(
            title: catalogSong.attributes.name.sanitizedTrackTitle,
            subtitle: catalogSong.attributes.artistName,
            trailingText: catalogSong.attributes.durationInMillis.map { formattedDuration(millis: $0) },
            artworkURL: artworkURL,
        )
    }

    init(audioTrack: AudioTrackRecord, artworkURL: URL? = nil) {
        let seconds = Int(audioTrack.durationSeconds)
        self.init(
            title: audioTrack.title.sanitizedTrackTitle,
            subtitle: [audioTrack.artistName, audioTrack.albumTitle].joinedForDisplay,
            trailingText: seconds > 0 ? formattedDuration(seconds: seconds) : nil,
            artworkURL: artworkURL,
        )
    }

    init(
        playbackTrack: PlaybackTrack,
        showsAlbumName: Bool = false,
        trailingText: String? = nil,
    ) {
        let subtitle: String = if showsAlbumName,
                                  let albumName = playbackTrack.albumName,
                                  !albumName.isEmpty
        {
            [playbackTrack.artistName, albumName].joinedForDisplay
        } else {
            playbackTrack.artistName
        }

        self.init(
            title: playbackTrack.title.sanitizedTrackTitle,
            subtitle: subtitle,
            trailingText: trailingText,
            artworkURL: playbackTrack.artworkURL,
        )
    }

    init(playlistEntry: PlaylistEntry, artworkURL: URL? = nil) {
        let subtitle = [playlistEntry.artistName, playlistEntry.albumTitle]
            .compactMap(\.self)
            .joinedForDisplay

        self.init(
            title: playlistEntry.title.sanitizedTrackTitle,
            subtitle: subtitle,
            trailingText: playlistEntry.durationMillis.map { formattedDuration(millis: $0) },
            artworkURL: artworkURL,
        )
    }
}
