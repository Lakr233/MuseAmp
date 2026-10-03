//
//  NowPlayingContentMapper.swift
//  MuseAmp
//
//  Created by @Lakr233 on 2026/04/14.
//

import Foundation
import MuseAmpPlayerKit

enum NowPlayingContentMapper {
    nonisolated static func makeContent(
        from snapshot: PlaybackSnapshot,
        cleanTitleEnabled: Bool = AppPreferences.isCleanSongTitleEnabled,
    ) -> AMNowPlayingContent {
        guard let track = snapshot.currentTrack else {
            return AMNowPlayingContent(
                trackID: "",
                title: String(localized: "Nothing Playing"),
                subtitle: String(localized: "Pick a song to get started"),
                hasActiveTrack: false,
                routeName: routeName(for: snapshot.outputDevice),
                routeSymbolName: routeSymbolName(for: snapshot.outputDevice),
            )
        }

        let title = cleanTitleEnabled
            ? TrackTitleSanitizer.sanitize(track.title, forceEnabled: true)
            : track.title

        return AMNowPlayingContent(
            trackID: track.id,
            title: title,
            subtitle: track.artistName,
            hasActiveTrack: true,
            routeName: routeName(for: snapshot.outputDevice),
            routeSymbolName: routeSymbolName(for: snapshot.outputDevice),
        )
    }

    nonisolated static func makeBackgroundSource(
        from snapshot: PlaybackSnapshot,
    ) -> NowPlayingControlIslandViewModel.BackgroundSource {
        guard let artworkURL = snapshot.currentTrack?.artworkURL else {
            return .idle
        }
        return .artwork(url: artworkURL)
    }

    nonisolated static func isPlaying(for state: PlaybackState) -> Bool {
        switch state {
        case .playing, .buffering:
            true
        case .idle, .paused, .error:
            false
        }
    }

    nonisolated static func isPreviousAvailable(for snapshot: PlaybackSnapshot) -> Bool {
        !snapshot.history.isEmpty
            || snapshot.currentTime > 3
            || (snapshot.repeatMode == .queue && !snapshot.queue.isEmpty)
    }

    nonisolated static func routeName(for outputDevice: PlaybackOutputDevice?) -> String {
        outputDevice?.name ?? String(localized: "iPhone")
    }

    nonisolated static func routeSymbolName(for outputDevice: PlaybackOutputDevice?) -> String {
        guard let outputDevice else {
            return "iphone"
        }

        let lowercasedName = outputDevice.name.lowercased()

        switch outputDevice.kind {
        case .builtInSpeaker:
            return "speaker.wave.2.fill"
        case .builtInReceiver:
            return "iphone"
        case .wiredHeadphones:
            return "headphones"
        case .bluetooth:
            if lowercasedName.contains("airpods max") {
                return "airpodsmax"
            }
            if lowercasedName.contains("airpods pro") {
                return "airpodspro"
            }
            if lowercasedName.contains("airpods") {
                return "airpods"
            }
            return "headphones"
        case .airPlay:
            if lowercasedName.contains("tv") {
                return "tv.fill"
            }
            return "airplayaudio"
        case .carAudio:
            return "car.fill"
        case .television:
            return "tv.fill"
        case .external:
            return "cable.connector"
        case .unknown:
            return "speaker.wave.2.fill"
        }
    }
}
