//
//  PlaylistSearchCell.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import AmMusicDatabaseKit
import UIKit

final class PlaylistSearchCell: PlaylistCell {
    static let searchReuseID = "PlaylistSearchCell"

    func configure(
        with playlist: Playlist,
        query: String,
        matchingSongNames: [String],
        fallbackSubtitle: String? = nil,
        apiClient: APIClient?,
        artworkCache: PlaylistCoverArtworkCache?,
        paths: LibraryPaths? = nil,
    ) {
        let artworkKey = artworkKey(for: playlist, sideLength: 44, scale: UIScreen.main.scale)
        super.configure(
            title: playlist.name,
            subtitle: nil,
            placeholderIcon: "music.note.list",
            roundArtwork: false,
        )

        if playlist.name.localizedCaseInsensitiveContains(query) {
            setAttributedTitle(SearchHighlightHelper.attributedString(
                text: playlist.name, query: query, font: .systemFont(ofSize: 16), color: .label,
            ))
        }

        if !matchingSongNames.isEmpty {
            let songText = matchingSongNames.prefix(3).joined(separator: ", ")
            let subtitle = matchingSongNames.count > 3
                ? "\(songText) + \(matchingSongNames.count - 3)"
                : songText
            setAttributedSubtitle(SearchHighlightHelper.attributedString(
                text: subtitle, query: query, font: .systemFont(ofSize: 13), color: .secondaryLabel,
            ))
        } else if let fallbackSubtitle {
            setAttributedSubtitle(NSAttributedString(
                string: fallbackSubtitle,
                attributes: [.font: UIFont.systemFont(ofSize: 13), .foregroundColor: UIColor.secondaryLabel],
            ))
        }

        loadCoverArtwork(
            for: playlist,
            artworkKey: artworkKey,
            shouldPreserve: false,
            apiClient: apiClient,
            artworkCache: artworkCache,
            paths: paths,
        )
    }
}
