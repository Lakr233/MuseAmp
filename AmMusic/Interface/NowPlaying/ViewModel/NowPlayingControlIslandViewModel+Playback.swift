import AmMusicPlayerKit
import UIKit

extension NowPlayingControlIslandViewModel {
    enum BackgroundSource: Equatable {
        case idle
        case artwork(url: URL)
    }

    struct Presentation {
        let content: Content
        let backgroundSource: BackgroundSource
        let shouldAnimatePlaybackStateChange: Bool
        let shouldAnimateTransition: Bool
    }

    @discardableResult
    func apply(snapshot: PlaybackSnapshot) -> Presentation {
        let previousTrackID = currentTrackID
        let previousContent = content
        let nextTrackID = snapshot.currentTrack?.id
        currentTrackID = nextTrackID

        let content = makeContent(from: snapshot)
        self.content = content

        return Presentation(
            content: content,
            backgroundSource: makeBackgroundSource(from: snapshot),
            shouldAnimatePlaybackStateChange: previousContent.isPlaying != content.isPlaying,
            shouldAnimateTransition: previousTrackID != nextTrackID
        )
    }

    func content(for snapshot: PlaybackSnapshot) -> Content {
        makeContent(from: snapshot)
    }

    func bindActions(
        onFavorite: @escaping () -> Void,
        onPrevious: @escaping () -> Void,
        onTogglePlayPause: @escaping () -> Void,
        onNext: @escaping () -> Void,
        onSeek: @escaping (TimeInterval) -> Void
    ) {
        self.onFavorite = onFavorite
        self.onPrevious = onPrevious
        self.onTogglePlayPause = onTogglePlayPause
        self.onNext = onNext
        self.onSeek = onSeek
    }
}

private extension NowPlayingControlIslandViewModel {
    func makeContent(from snapshot: PlaybackSnapshot) -> Content {
        guard let track = snapshot.currentTrack else {
            return Content(
                title: String(localized: "Nothing Playing"),
                artist: String(localized: "Pick a song to get started"),
                currentTime: 0,
                duration: 0,
                hasActiveTrack: false,
                isPreviousAvailable: false,
                isPlaying: false,
                isFavorite: false,
                routeName: routeName(for: snapshot.outputDevice),
                routeSymbolName: routeSymbolName(for: snapshot.outputDevice)
            )
        }

        let duration = max(snapshot.duration, track.durationInSeconds ?? 0)

        return Content(
            title: track.title,
            artist: track.artistName,
            currentTime: snapshot.currentTime,
            duration: duration,
            hasActiveTrack: true,
            isPreviousAvailable: isPreviousAvailable(for: snapshot),
            isPlaying: isPlaying(for: snapshot.state),
            isFavorite: snapshot.isCurrentTrackLiked,
            routeName: routeName(for: snapshot.outputDevice),
            routeSymbolName: routeSymbolName(for: snapshot.outputDevice)
        )
    }

    func makeBackgroundSource(from snapshot: PlaybackSnapshot) -> BackgroundSource {
        guard let artworkURL = snapshot.currentTrack?.artworkURL else {
            return .idle
        }
        return .artwork(url: artworkURL)
    }

    func isPlaying(for state: PlaybackState) -> Bool {
        switch state {
        case .playing, .buffering:
            true
        case .idle, .paused, .error:
            false
        }
    }

    func isPreviousAvailable(for snapshot: PlaybackSnapshot) -> Bool {
        !snapshot.history.isEmpty
            || snapshot.currentTime > 3
            || (snapshot.repeatMode == .queue && !snapshot.queue.isEmpty)
    }

    func routeName(for outputDevice: PlaybackOutputDevice?) -> String {
        outputDevice?.name ?? String(localized: "iPhone")
    }

    func routeSymbolName(for outputDevice: PlaybackOutputDevice?) -> String {
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
