//
//  LibraryChangeNotifications.swift
//  MuseAmp
//
//  Created by @Lakr233 on 2026/04/11.
//

import Foundation

extension Notification.Name {
    nonisolated static let libraryDidSync = Notification.Name("amusic.libraryDidSync")
    nonisolated static let artworkDidUpdate = Notification.Name("amusic.artworkDidUpdate")
    nonisolated static let playlistArtworkDidUpdate = Notification.Name("amusic.playlistArtworkDidUpdate")
    nonisolated static let lyricsDidUpdate = Notification.Name("amusic.lyricsDidUpdate")
    nonisolated static let serverConfigurationDidChange = Notification.Name("amusic.serverConfigurationDidChange")
    nonisolated static let playHistoryDidChange = Notification.Name("amusic.playHistoryDidChange")
}

enum AppNotificationUserInfoKey {
    nonisolated static let trackIDs = "trackIDs"
    nonisolated static let playlistIDs = "playlistIDs"
}
