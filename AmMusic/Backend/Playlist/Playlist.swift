import AmMusicDatabaseKit
import Foundation

nonisolated extension AmMusicDatabaseKit.Playlist {
    static let likedSongsPlaylistID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    var isLikedSongsPlaylist: Bool {
        id == Self.likedSongsPlaylistID
    }

    var songs: [PlaylistEntry] {
        get { entries }
        set { entries = newValue }
    }
}

nonisolated enum LikedToggleResult: Equatable {
    case liked
    case unliked
    case playlistUnavailable
}
