import AmMusicDatabaseKit
import AmMusicKit
import Combine
import Foundation

extension Notification.Name {
    static let playlistsDidChange = Notification.Name("amusic.playlistsDidChange")
}

final class PlaylistStore {
    let databaseManager: DatabaseManager
    let legacyFileURL: URL?
    var playlistsChangedCancellable: AnyCancellable?

    var playlists: [Playlist] = []

    var onSongAdded: ((PlaylistEntry) -> Void)?

    init(database: MusicLibraryDatabase, legacyFileURL: URL? = nil) {
        databaseManager = database.databaseManager
        self.legacyFileURL = legacyFileURL

        bindDatabaseEvents()
        migrateLegacyPlaylistsIfNeeded()
        reload()
        syncLikedSongsNameToCurrentLocale()
    }

    @discardableResult
    func createPlaylist(id: UUID = UUID(), name: String, coverImageData: Data? = nil) -> Playlist {
        let previousPlaylists = playlists
        let candidate = Playlist(id: id, name: name, coverImageData: coverImageData)
        do {
            _ = try send(.importLegacyPlaylists([candidate]))
        } catch {
            AppLog.error(self, "createPlaylist failed id=\(id.uuidString) error=\(error)")
        }
        reload()
        notifyIfNeeded(previousPlaylists: previousPlaylists)
        return playlist(for: id) ?? candidate
    }

    func deletePlaylist(id: UUID) {
        performMutation(
            action: "deletePlaylist id=\(id.uuidString)",
            previousPlaylists: playlists
        ) {
            _ = try send(.deletePlaylist(id: id))
        }
    }

    func deletePlaylists(ids: [UUID]) {
        performMutation(
            action: "deletePlaylists count=\(ids.count)",
            previousPlaylists: playlists
        ) {
            for id in ids {
                _ = try send(.deletePlaylist(id: id))
            }
        }
    }

    func renamePlaylist(id: UUID, name: String) {
        performMutation(
            action: "renamePlaylist id=\(id.uuidString)",
            previousPlaylists: playlists
        ) {
            _ = try send(.renamePlaylist(id: id, name: name))
        }
    }

    func updateCover(id: UUID, imageData: Data?) {
        performMutation(
            action: "updateCover id=\(id.uuidString)",
            previousPlaylists: playlists
        ) {
            _ = try send(.updatePlaylistCover(id: id, imageData: imageData))
        }
    }

    @discardableResult
    func addSong(_ song: PlaylistEntry, to playlistID: UUID) -> Bool {
        let previousPlaylists = playlists
        let entry = PlaylistEntry(
            trackID: song.trackID,
            title: song.title,
            artistName: song.artistName,
            albumID: song.albumID,
            albumTitle: song.albumTitle,
            artworkURL: song.artworkURL,
            durationMillis: song.durationMillis,
            trackNumber: song.trackNumber,
            lyrics: song.lyrics
        )
        do {
            _ = try send(.addPlaylistEntry(entry, playlistID: playlistID))
        } catch {
            AppLog.error(
                self, "addSong failed trackID=\(song.trackID) playlistID=\(playlistID.uuidString) error=\(error)"
            )
        }
        reload()
        let inserted = playlists != previousPlaylists
        if inserted {
            onSongAdded?(song)
            NotificationCenter.default.post(name: .playlistsDidChange, object: self)
        }
        return inserted
    }

    func updateLyrics(_ lyrics: String, trackID: String, playlistID: UUID) {
        performMutation(
            action: "updateLyrics trackID=\(trackID) playlistID=\(playlistID.uuidString)",
            previousPlaylists: playlists
        ) {
            _ = try send(.updateEntryLyrics(lyrics: lyrics, trackID: trackID, playlistID: playlistID))
        }
    }

    func removeSong(at songIndex: Int, from playlistID: UUID) {
        let previousPlaylists = playlists
        do {
            _ = try send(.removePlaylistEntry(index: songIndex, playlistID: playlistID))
        } catch {
            AppLog.error(
                self,
                "removeSong failed index=\(songIndex) playlistID=\(playlistID.uuidString) error=\(error)"
            )
        }
        finishMutation(previousPlaylists: previousPlaylists, pruneLikedPlaylistIfNeededFor: playlistID)
    }

    func updateSong(in playlistID: UUID, at index: Int, with song: PlaylistEntry) {
        guard var playlist = playlist(for: playlistID), playlist.songs.indices.contains(index) else {
            return
        }

        playlist.songs[index] = song
        let previousPlaylists = playlists
        do {
            _ = try send(.clearPlaylistEntries(playlistID: playlistID))
            for entry in playlist.songs {
                _ = try send(.addPlaylistEntry(entry, playlistID: playlistID))
            }
        } catch {
            AppLog.error(
                self,
                "updateSong failed playlistID=\(playlistID.uuidString) index=\(index) trackID=\(song.trackID) error=\(error)"
            )
        }
        reload()
        notifyIfNeeded(previousPlaylists: previousPlaylists)
    }

    func refreshSongs(in playlistID: UUID, using apiClient: APIClient) async -> Int {
        reload()
        guard let currentPlaylist = playlist(for: playlistID), !currentPlaylist.songs.isEmpty else {
            return 0
        }

        let songs = currentPlaylist.songs
        let fetched: [String: PlaylistEntry] = await withTaskGroup(of: (String, PlaylistEntry?).self) {
            group in
            for entry in songs {
                group.addTask {
                    guard let catalogSong = try? await apiClient.song(id: entry.trackID) else {
                        return (entry.trackID, nil)
                    }
                    let refreshed = PlaylistEntry(
                        trackID: catalogSong.id,
                        title: catalogSong.attributes.name,
                        artistName: catalogSong.attributes.artistName,
                        albumID: catalogSong.relationships?.albums?.data.first?.id,
                        albumTitle: catalogSong.attributes.albumName,
                        artworkURL: catalogSong.attributes.artwork?.url,
                        durationMillis: catalogSong.attributes.durationInMillis,
                        trackNumber: catalogSong.attributes.trackNumber
                    )
                    return (entry.trackID, refreshed)
                }
            }

            var results: [String: PlaylistEntry] = [:]
            for await (trackID, refreshed) in group {
                if let refreshed {
                    results[trackID] = refreshed
                }
            }
            return results
        }

        var updatedCount = 0
        reload()
        guard let latestPlaylist = playlist(for: playlistID) else {
            return 0
        }
        for (index, existing) in latestPlaylist.songs.enumerated() {
            guard let refreshed = fetched[existing.trackID] else {
                continue
            }
            let merged = PlaylistEntry(
                entryID: existing.entryID,
                trackID: existing.trackID,
                title: refreshed.title,
                artistName: refreshed.artistName,
                albumID: refreshed.albumID ?? existing.albumID,
                albumTitle: refreshed.albumTitle ?? existing.albumTitle,
                artworkURL: refreshed.artworkURL,
                durationMillis: refreshed.durationMillis ?? existing.durationMillis,
                trackNumber: refreshed.trackNumber ?? existing.trackNumber,
                lyrics: existing.lyrics
            )
            let nameChanged = merged.title != existing.title
            let artistChanged = merged.artistName != existing.artistName
            let artworkChanged = merged.artworkURL != existing.artworkURL
            let albumIDChanged = merged.albumID != existing.albumID
            let albumNameChanged = merged.albumTitle != existing.albumTitle
            let durationChanged = merged.durationMillis != existing.durationMillis
            let trackNumChanged = merged.trackNumber != existing.trackNumber
            guard
                nameChanged || artistChanged || artworkChanged
                || albumIDChanged || albumNameChanged || durationChanged || trackNumChanged
            else {
                continue
            }
            updateSong(in: playlistID, at: index, with: merged)
            updatedCount += 1
        }

        AppLog.info(
            self,
            "refreshSongs playlistID=\(playlistID.uuidString) fetched=\(fetched.count) updated=\(updatedCount)"
        )
        return updatedCount
    }

    func moveSong(in playlistID: UUID, from source: Int, to destination: Int) {
        performMutation(
            action:
            "moveSong playlistID=\(playlistID.uuidString) source=\(source) destination=\(destination)",
            previousPlaylists: playlists
        ) {
            _ = try send(.movePlaylistEntry(playlistID: playlistID, from: source, to: destination))
        }
    }

    @discardableResult
    func duplicatePlaylist(id: UUID) -> Playlist? {
        guard playlist(for: id) != nil else {
            return nil
        }

        let previousPlaylists = playlists
        var duplicated: Playlist?
        do {
            let result = try send(.duplicatePlaylist(id: id))
            if case let .duplicatedPlaylist(playlist) = result {
                duplicated = playlist
            }
        } catch {
            AppLog.error(self, "duplicatePlaylist failed id=\(id.uuidString) error=\(error)")
        }
        reload()
        notifyIfNeeded(previousPlaylists: previousPlaylists)
        return duplicated
    }

    func clearSongs(in playlistID: UUID) {
        guard let playlist = playlist(for: playlistID), !playlist.songs.isEmpty else {
            return
        }
        let previousPlaylists = playlists
        do {
            _ = try send(.clearPlaylistEntries(playlistID: playlistID))
        } catch {
            AppLog.error(self, "clearSongs failed playlistID=\(playlistID.uuidString) error=\(error)")
        }
        finishMutation(previousPlaylists: previousPlaylists, pruneLikedPlaylistIfNeededFor: playlistID)
    }

    func mergeSongs(from sourceID: UUID, into targetID: UUID) {
        guard let source = playlist(for: sourceID), !source.songs.isEmpty else {
            return
        }
        for song in source.songs {
            _ = addSong(song, to: targetID)
        }
    }

    func playlist(for id: UUID) -> Playlist? {
        playlists.first { $0.id == id }
    }

    func likedSongsPlaylist() -> Playlist? {
        playlist(for: Playlist.likedSongsPlaylistID)
    }

    func isLiked(trackID: String) -> Bool {
        likedSongsPlaylist()?.songs.contains { $0.trackID == trackID } == true
    }

    @discardableResult
    func toggleLiked(_ song: PlaylistEntry) -> LikedToggleResult {
        guard let likedPlaylist = ensureLikedSongsPlaylist() else {
            return .playlistUnavailable
        }
        if isLiked(trackID: song.trackID) {
            removeSong(trackID: song.trackID, from: likedPlaylist.id)
            return .unliked
        }
        _ = addSong(song, to: likedPlaylist.id)
        return .liked
    }

    func reload() {
        do {
            playlists = try databaseManager.fetchPlaylists()
        } catch {
            AppLog.error(self, "reload failed: \(error)")
        }
    }

    func removeSong(trackID: String, from playlistID: UUID) {
        guard let songIndex = playlist(for: playlistID)?.songs.firstIndex(where: { $0.trackID == trackID })
        else {
            return
        }
        removeSong(at: songIndex, from: playlistID)
    }
}
