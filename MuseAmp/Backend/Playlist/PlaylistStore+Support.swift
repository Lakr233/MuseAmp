//
//  PlaylistStore+Support.swift
//  MuseAmp
//
//  Created by @Lakr233 on 2026/04/11.
//

import Combine
import Foundation
import MuseAmpDatabaseKit
import SubsonicClientKit

extension PlaylistStore {
    func bindDatabaseEvents() {
        databaseManager.events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                guard case .playlistsChanged = event else {
                    return
                }
                guard let self else {
                    return
                }
                let previousPlaylists = playlists
                reload()
                notifyIfNeeded(previousPlaylists: previousPlaylists)
            }
            .store(in: &cancellables)
    }

    var likedSongsPlaylistDefaultName: String {
        String(localized: "Liked Songs")
    }

    func send(_ command: LibraryCommand) throws -> LibraryCommandResult {
        try databaseManager.sendSynchronously(command)
    }

    func syncLikedSongsNameToCurrentLocale() {
        guard let playlist = likedSongsPlaylist(),
              playlist.name != likedSongsPlaylistDefaultName
        else {
            return
        }
        do {
            _ = try send(.renamePlaylist(id: playlist.id, name: likedSongsPlaylistDefaultName))
            reload()
        } catch {
            AppLog.error(self, "syncLikedSongsNameToCurrentLocale rename failed error=\(error)")
        }
    }

    @discardableResult
    func ensureLikedSongsPlaylist() -> Playlist? {
        if let playlist = likedSongsPlaylist() {
            backfillLikedSongsPlaylistMetadataIfNeeded(playlist)
            return likedSongsPlaylist()
        }

        _ = createPlaylist(
            id: Playlist.likedSongsPlaylistID,
            name: likedSongsPlaylistDefaultName,
            coverImageData: LikedSongsPlaylistArtwork.makePNGData(),
        )
        return likedSongsPlaylist()
    }

    func backfillLikedSongsPlaylistMetadataIfNeeded(_ playlist: Playlist) {
        guard playlist.isLikedSongsPlaylist else {
            return
        }

        let shouldUpdateName = playlist.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let shouldUpdateCover = playlist.coverImageData == nil
        guard shouldUpdateName || shouldUpdateCover else {
            return
        }

        let previousPlaylists = playlists
        if shouldUpdateName {
            do {
                _ = try send(.renamePlaylist(id: playlist.id, name: likedSongsPlaylistDefaultName))
            } catch {
                AppLog.error(
                    self, "backfillLikedSongsPlaylistMetadataIfNeeded rename failed error=\(error)",
                )
            }
        }
        if shouldUpdateCover {
            do {
                _ = try send(
                    .updatePlaylistCover(id: playlist.id, imageData: LikedSongsPlaylistArtwork.makePNGData()),
                )
            } catch {
                AppLog.error(
                    self, "backfillLikedSongsPlaylistMetadataIfNeeded cover update failed error=\(error)",
                )
            }
        }
        reload()
        notifyIfNeeded(previousPlaylists: previousPlaylists)
    }

    func finishMutation(
        previousPlaylists: [Playlist], pruneLikedPlaylistIfNeededFor playlistID: UUID? = nil,
    ) {
        reload()

        if playlistID == Playlist.likedSongsPlaylistID,
           likedSongsPlaylist()?.songs.isEmpty == true
        {
            do {
                _ = try send(.deletePlaylist(id: Playlist.likedSongsPlaylistID))
            } catch {
                AppLog.error(self, "finishMutation prune liked playlist failed error=\(error)")
            }
            reload()
        }

        notifyIfNeeded(previousPlaylists: previousPlaylists)
    }

    func notifyIfNeeded(previousPlaylists: [Playlist]) {
        guard playlists != previousPlaylists else {
            return
        }
        NotificationCenter.default.post(name: .playlistsDidChange, object: self)
    }

    func performMutation(
        action: String,
        operation: () throws -> Void,
    ) {
        let previousPlaylists = playlists
        do {
            try operation()
        } catch {
            AppLog.error(self, "\(action) failed error=\(error)")
        }
        reload()
        notifyIfNeeded(previousPlaylists: previousPlaylists)
    }
}
