//
//  PlaylistCell.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import AmMusicDatabaseKit
import UIKit

class PlaylistCell: AmMediaCell {
    static let cellReuseID = "PlaylistCell"
    private static let renderedArtworkCache = NSCache<NSString, UIImage>()

    private var representedPlaylistID: UUID?
    private var representedArtworkKey: String?
    private var hasLoadedArtwork = false
    private var coverTask: Task<Void, Never>?
    private let artworkSideLength: CGFloat = 44

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    func configure(with playlist: Playlist, subtitle: String, apiClient: APIClient?, artworkCache: PlaylistCoverArtworkCache?, paths: LibraryPaths? = nil) {
        let artworkKey = artworkKey(for: playlist, sideLength: artworkSideLength, scale: UIScreen.main.scale)
        let shouldPreserveArtwork = representedPlaylistID == playlist.id
            && representedArtworkKey == artworkKey
            && hasLoadedArtwork

        representedPlaylistID = playlist.id
        representedArtworkKey = artworkKey
        super.configure(
            title: playlist.name,
            subtitle: subtitle,
            placeholderIcon: "music.note.list",
            roundArtwork: false,
        )

        loadCoverArtwork(for: playlist, artworkKey: artworkKey, shouldPreserve: shouldPreserveArtwork, apiClient: apiClient, artworkCache: artworkCache, paths: paths)
    }

    override func prepareForReuse() {
        coverTask?.cancel()
        coverTask = nil
        representedPlaylistID = nil
        representedArtworkKey = nil
        hasLoadedArtwork = false
        super.prepareForReuse()
    }

    // MARK: - Artwork

    func loadCoverArtwork(for playlist: Playlist, artworkKey: String, shouldPreserve: Bool, apiClient: APIClient?, artworkCache: PlaylistCoverArtworkCache?, paths: LibraryPaths? = nil) {
        coverTask?.cancel()
        coverTask = nil

        if let coverData = playlist.coverImageData, let image = UIImage(data: coverData) {
            Self.renderedArtworkCache.setObject(image, forKey: artworkKey as NSString)
            hasLoadedArtwork = true
            setArtworkImage(image)
            return
        }

        guard !playlist.songs.isEmpty else {
            representedArtworkKey = nil
            hasLoadedArtwork = false
            resetArtwork()
            return
        }

        if shouldPreserve { return }

        if let cachedImage = Self.renderedArtworkCache.object(forKey: artworkKey as NSString) {
            hasLoadedArtwork = true
            setArtworkImage(cachedImage)
            return
        }

        hasLoadedArtwork = false
        resetArtwork()
        let apiBaseURL = apiClient?.baseURL
        coverTask = Task { @MainActor [weak self, playlist, apiBaseURL, artworkKey, paths] in
            guard let artworkCache else { return }
            let image = await artworkCache.image(
                for: playlist,
                sideLength: self?.artworkSideLength ?? 44,
                scale: UIScreen.main.scale,
            ) { entry, width, height in
                if let paths {
                    let localURL = paths.artworkCacheURL(for: entry.trackID)
                    if FileManager.default.fileExists(atPath: localURL.path) {
                        return localURL
                    }
                }
                return APIClient.resolveMediaURL(entry.artworkURL, width: width, height: height, baseURL: apiBaseURL)
            }

            guard !Task.isCancelled else { return }
            guard self?.representedPlaylistID == playlist.id else { return }
            guard self?.representedArtworkKey == artworkKey else { return }
            Self.renderedArtworkCache.setObject(image, forKey: artworkKey as NSString)
            self?.setArtworkImage(image)
            self?.hasLoadedArtwork = true
        }
    }

    func artworkKey(for playlist: Playlist, sideLength: CGFloat, scale: CGFloat) -> String {
        let sidePixels = max(Int((sideLength * scale).rounded()), 1)
        let timestamp = Int((playlist.updatedAt.timeIntervalSince1970 * 1000).rounded())
        if playlist.coverImageData != nil {
            return "custom-\(playlist.id.uuidString)-\(timestamp)-\(sidePixels)"
        }
        return "generated-\(playlist.id.uuidString)-\(timestamp)-\(playlist.songs.count)-\(sidePixels)"
    }
}
