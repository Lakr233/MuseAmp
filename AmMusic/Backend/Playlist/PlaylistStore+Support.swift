import AmMusicDatabaseKit
import AmMusicKit
import Combine
import Foundation

extension PlaylistStore {
    func bindDatabaseEvents() {
        playlistsChangedCancellable = databaseManager.events
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

    func ensureLikedSongsPlaylist() -> Playlist? {
        if let playlist = likedSongsPlaylist() {
            backfillLikedSongsPlaylistMetadataIfNeeded(playlist)
            return likedSongsPlaylist()
        }

        _ = createPlaylist(
            id: Playlist.likedSongsPlaylistID,
            name: likedSongsPlaylistDefaultName,
            coverImageData: LikedSongsPlaylistArtwork.makePNGData()
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
                    self, "backfillLikedSongsPlaylistMetadataIfNeeded rename failed error=\(error)"
                )
            }
        }
        if shouldUpdateCover {
            do {
                _ = try send(
                    .updatePlaylistCover(id: playlist.id, imageData: LikedSongsPlaylistArtwork.makePNGData())
                )
            } catch {
                AppLog.error(
                    self, "backfillLikedSongsPlaylistMetadataIfNeeded cover update failed error=\(error)"
                )
            }
        }
        reload()
        notifyIfNeeded(previousPlaylists: previousPlaylists)
    }

    func finishMutation(
        previousPlaylists: [Playlist], pruneLikedPlaylistIfNeededFor playlistID: UUID? = nil
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

    func migrateLegacyPlaylistsIfNeeded() {
        let existingPlaylists: [AmMusicDatabaseKit.Playlist]
        do {
            existingPlaylists = try databaseManager.fetchPlaylists()
        } catch {
            AppLog.error(self, "migrateLegacyPlaylistsIfNeeded fetch existing failed error=\(error)")
            return
        }
        guard existingPlaylists.isEmpty else {
            return
        }
        guard let legacyFileURL else {
            return
        }
        guard FileManager.default.fileExists(atPath: legacyFileURL.path) else {
            return
        }

        let data: Data
        do {
            data = try Data(contentsOf: legacyFileURL)
        } catch {
            AppLog.error(
                self,
                "migrateLegacyPlaylistsIfNeeded read failed path=\(legacyFileURL.lastPathComponent) error=\(error)"
            )
            return
        }

        guard let legacyPlaylists = decodeLegacyPlaylists(from: data) else {
            AppLog.warning(self, "migrateLegacyPlaylistsIfNeeded decode failed")
            return
        }

        do {
            _ = try send(.importLegacyPlaylists(legacyPlaylists))
        } catch {
            AppLog.error(
                self,
                "migrateLegacyPlaylistsIfNeeded import failed count=\(legacyPlaylists.count) error=\(error)"
            )
            return
        }

        let migratedURL = legacyFileURL.appendingPathExtension("migrated")
        if FileManager.default.fileExists(atPath: migratedURL.path) {
            do {
                try FileManager.default.removeItem(at: migratedURL)
            } catch {
                AppLog.error(
                    self, "migrateLegacyPlaylistsIfNeeded remove existing migrated file failed error=\(error)"
                )
            }
        }
        do {
            try FileManager.default.moveItem(at: legacyFileURL, to: migratedURL)
        } catch {
            AppLog.error(self, "migrateLegacyPlaylistsIfNeeded move legacy file failed error=\(error)")
        }
    }

    func performMutation(
        action: String,
        previousPlaylists: [Playlist],
        operation: () throws -> Void
    ) {
        do {
            try operation()
        } catch {
            AppLog.error(self, "\(action) failed error=\(error)")
        }
        reload()
        notifyIfNeeded(previousPlaylists: previousPlaylists)
    }

    func decodeLegacyPlaylists(from data: Data) -> [Playlist]? {
        if let playlists = try? JSONDecoder().decode([Playlist].self, from: data) {
            return playlists
        }

        let legacyPlaylists = try? JSONDecoder().decode([LegacyPlaylist].self, from: data)
        return legacyPlaylists?.map(\.playlist)
    }
}
