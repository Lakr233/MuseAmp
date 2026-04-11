//
//  PlaybackController.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import AmMusicDatabaseKit
import AmMusicKit
import AmMusicPlayerKit
import AVFoundation
import Combine
import Foundation

enum PlayNextResult {
    case played(Int)
    case queued(Int)
    case resumed
    case alreadyPlaying
    case alreadyQueued
    case failed
}

@MainActor
final class PlaybackController: ObservableObject {
    struct QueueState {
        var currentSource: PlaybackSource?
        var trackLookup: [String: PlaybackTrack] = [:]
        var itemCache: [String: PlayerItem] = [:]

        mutating func reset() {
            currentSource = nil
            trackLookup.removeAll()
        }
    }

    struct RestoreState {
        var didAttemptPersistedRestore = false
    }

    struct SeekState {
        var pendingSeekSnapshotTime: TimeInterval?
    }

    static let periodicPlaybackStatusLogInterval: TimeInterval = 15
    nonisolated static let queueItemIDPrefix = "queue-item"

    @Published var snapshot = PlaybackSnapshot.empty
    var latestSnapshot = PlaybackSnapshot.empty
    let playbackTimeSubject = PassthroughSubject<(currentTime: TimeInterval, duration: TimeInterval), Never>()

    let database: MusicLibraryDatabase
    let downloadStore: DownloadStore
    let metadataReader: EmbeddedMetadataReader
    let paths: LibraryPaths
    let playlistStore: PlaylistStore
    let player: AmMusicPlayerKit.MusicPlayer
    let sessionStore: PlaybackSessionStore

    var queueState = QueueState()
    var restoreState = RestoreState()
    var seekState = SeekState()
    var playlistsDidChangeObserver: NSObjectProtocol?
    var playbackStatusLogTimer: Timer?
    var routeChangeObserver: NSObjectProtocol?
    var isUIPublishingSuspended = false

    init(
        apiClient _: APIClient,
        database: MusicLibraryDatabase,
        downloadStore: DownloadStore,
        metadataReader: EmbeddedMetadataReader,
        paths: LibraryPaths,
        playlistStore: PlaylistStore,
        player: AmMusicPlayerKit.MusicPlayer,
        sessionStore: PlaybackSessionStore? = nil,
    ) {
        self.database = database
        self.downloadStore = downloadStore
        self.metadataReader = metadataReader
        self.paths = paths
        self.playlistStore = playlistStore
        self.player = player
        self.sessionStore = sessionStore ?? PlaybackSessionStore(fileURL: paths.playbackStateURL)
        player.delegate = self
        player.configureLikeCommand(
            title: String(localized: "Like"),
            shortTitle: String(localized: "Like"),
        ) { [weak self] in
            guard let self else {
                return false
            }
            return toggleLikedCurrentTrack() != .playlistUnavailable
        }
        playlistsDidChangeObserver = NotificationCenter.default.addObserver(
            forName: .playlistsDidChange,
            object: playlistStore,
            queue: .main,
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshSnapshot(persistState: true)
            }
        }
        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main,
        ) { [weak self] notification in
            let reason = (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt)
                .flatMap(AVAudioSession.RouteChangeReason.init(rawValue:))
            Task { @MainActor [weak self] in
                self?.handleRouteChange(reason: reason)
            }
        }
        refreshSnapshot()
    }

    convenience init(
        apiClient: APIClient,
        database: MusicLibraryDatabase,
        downloadStore: DownloadStore,
        metadataReader: EmbeddedMetadataReader,
        paths: LibraryPaths,
        playlistStore: PlaylistStore,
        sessionStore: PlaybackSessionStore? = nil,
    ) {
        self.init(
            apiClient: apiClient,
            database: database,
            downloadStore: downloadStore,
            metadataReader: metadataReader,
            paths: paths,
            playlistStore: playlistStore,
            player: AmMusicPlayerKit.MusicPlayer(logger: Self.playerLogger),
            sessionStore: sessionStore,
        )
    }

    // MARK: - Playback Control

    @discardableResult
    func play(
        tracks: [PlaybackTrack],
        startAt startIndex: Int = 0,
        source: PlaybackSource,
        shuffle: Bool = false,
    ) async -> Bool {
        guard !tracks.isEmpty else {
            AppLog.warning(self, "play ignored for empty track list")
            return false
        }

        let resolvedItems = await resolvePlayableItems(for: tracks)
        guard !resolvedItems.isEmpty else {
            AppLog.warning(self, "play found no playable items source=\(String(describing: source))")
            return false
        }

        let orderedItems = resolvedItems.map(\.item)
        let preferredStart = preferredStartIndex(for: resolvedItems, requestedIndex: startIndex)

        queueState.currentSource = source
        queueState.trackLookup = Dictionary(uniqueKeysWithValues: resolvedItems.map { ($0.item.id, $0.track) })
        player.startPlayback(items: orderedItems, startIndex: preferredStart, shuffle: shuffle)
        return true
    }

    @discardableResult
    func play(
        track: PlaybackTrack,
        in tracks: [PlaybackTrack],
        source: PlaybackSource,
        shuffle: Bool = false,
    ) async -> Bool {
        let trackIDs = tracks.map(\.id)
        let startIndex = trackIDs.firstIndex(of: track.id) ?? 0
        let queueTracks = tracks.isEmpty ? [track] : tracks
        return await play(tracks: queueTracks, startAt: startIndex, source: source, shuffle: shuffle)
    }

    @discardableResult
    func playNext(_ tracks: [PlaybackTrack]) async -> PlayNextResult {
        guard !tracks.isEmpty else { return .failed }
        if player.queue.totalCount == 0 {
            let started = await play(tracks: tracks, source: .adHoc(name: "Queue"))
            return started ? .played(tracks.count) : .failed
        }

        if tracks.count == 1, let track = tracks.first {
            if track.id == latestSnapshot.currentTrack?.id {
                if latestSnapshot.state == .paused {
                    AppLog.info(self, "playNext: resuming paused track trackID=\(track.id)")
                    player.play()
                    return .resumed
                }
                AppLog.info(self, "playNext: track is currently playing, no-op trackID=\(track.id)")
                return .alreadyPlaying
            }
            if let nextTrack = latestSnapshot.upcoming.first, nextTrack.id == track.id {
                AppLog.info(self, "playNext: track is already next, no-op trackID=\(track.id)")
                return .alreadyQueued
            }
        }

        let resolvedItems = await resolvePlayableItems(for: tracks)
        guard !resolvedItems.isEmpty else { return .failed }
        for resolvedItem in resolvedItems {
            queueState.trackLookup[resolvedItem.item.id] = resolvedItem.track
        }
        player.playNext(resolvedItems.map(\.item))
        return .queued(resolvedItems.count)
    }

    @discardableResult
    func addToQueue(_ tracks: [PlaybackTrack]) async -> Int {
        guard !tracks.isEmpty else { return 0 }
        if player.queue.totalCount == 0 {
            let started = await play(tracks: tracks, source: .adHoc(name: "Queue"))
            return started ? tracks.count : 0
        }

        let resolvedItems = await resolvePlayableItems(for: tracks)
        guard !resolvedItems.isEmpty else { return 0 }
        for resolvedItem in resolvedItems {
            queueState.trackLookup[resolvedItem.item.id] = resolvedItem.track
        }
        player.addToQueue(resolvedItems.map(\.item))
        return resolvedItems.count
    }

    func togglePlayPause() {
        AppLog.info(self, "togglePlayPause current=\(string(for: player.state))")
        player.togglePlayPause()
    }

    func play() {
        AppLog.info(self, "play requested current=\(string(for: player.state))")
        player.play()
    }

    func pause() {
        AppLog.info(self, "pause requested current=\(string(for: player.state))")
        player.pause()
    }

    func next() {
        AppLog.info(self, "next requested trackID=\(latestSnapshot.currentTrack?.id ?? "nil") upcoming=\(latestSnapshot.upcoming.count)")
        player.next()
    }

    func previous() {
        let willRestart = player.currentTime > 3
        AppLog.info(self, "previous requested trackID=\(latestSnapshot.currentTrack?.id ?? "nil") currentTime=\(formattedPlaybackTime(player.currentTime)) willRestart=\(willRestart)")
        player.previous()
        if willRestart {
            seekState.pendingSeekSnapshotTime = 0
            refreshSnapshot(currentTime: 0, duration: player.duration, persistState: true)
        }
    }

    func restartCurrentTrack() {
        guard player.currentItem != nil else {
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            seekState.pendingSeekSnapshotTime = 0
            _ = await player.seek(to: 0)
            player.play()
            refreshSnapshot(currentTime: 0, duration: player.duration, persistState: true)
        }
    }

    func skipToUpcomingTrack(at index: Int) {
        guard latestSnapshot.upcoming.indices.contains(index) else {
            return
        }
        player.skip(to: index)
    }

    func removeTracksFromQueue(trackIDs: Set<String>) {
        guard !trackIDs.isEmpty else { return }
        let upcoming = player.queue.upcoming
        var removedCount = 0
        for item in upcoming {
            let sourceID = Self.sourceTrackID(for: item.id)
            if trackIDs.contains(sourceID) {
                player.removeFromQueue(id: item.id)
                removedCount += 1
            }
        }
        if removedCount > 0 {
            AppLog.info(self, "removeTracksFromQueue removed=\(removedCount) requested=\(trackIDs.count)")
        }
    }

    func removeFromQueue(at queueIndex: Int) {
        guard let playerIndex = latestSnapshot.playerIndex,
              queueIndex != playerIndex,
              queueIndex > playerIndex
        else {
            return
        }
        let upcomingIndex = queueIndex - playerIndex - 1
        AppLog.info(self, "removeFromQueue queueIndex=\(queueIndex) upcomingIndex=\(upcomingIndex)")
        player.removeFromQueue(at: upcomingIndex)
    }

    func skipToQueueTrack(at index: Int) {
        guard latestSnapshot.queue.indices.contains(index),
              let playerIndex = latestSnapshot.playerIndex
        else {
            return
        }

        guard index != playerIndex else {
            restartCurrentTrack()
            return
        }

        player.skipToQueueIndex(index)
    }

    func seek(to seconds: TimeInterval) {
        AppLog.info(self, "seek requested target=\(formattedPlaybackTime(max(seconds, 0))) from=\(formattedPlaybackTime(player.currentTime))")
        let targetTime = max(seconds, 0)
        seekState.pendingSeekSnapshotTime = targetTime
        refreshSnapshot(currentTime: targetTime, duration: player.duration)

        Task { [weak self] in
            guard let self else { return }
            await player.seek(to: targetTime)
            await MainActor.run {
                self.refreshSnapshot(currentTime: targetTime, duration: self.player.duration, persistState: true)
            }
        }
    }

    func setRepeatMode(_ mode: RepeatMode) {
        AppLog.info(self, "setRepeatMode from=\(string(for: player.repeatMode)) to=\(string(for: mode))")
        player.repeatMode = mode
        refreshSnapshot(persistState: true)
    }

    func setShuffle(_ enabled: Bool) {
        AppLog.info(self, "setShuffle enabled=\(enabled)")
        player.shuffled = enabled
    }

    @discardableResult
    func shuffleUpcomingQueue() async -> Int {
        let tracks = latestSnapshot.upcoming
        guard !tracks.isEmpty else {
            return 0
        }

        let resolvedItems = await resolvePlayableItems(for: tracks.shuffled())
        guard !resolvedItems.isEmpty else {
            return 0
        }

        for resolvedItem in resolvedItems {
            queueState.trackLookup[resolvedItem.item.id] = resolvedItem.track
        }

        player.replaceUpcomingQueue(resolvedItems.map(\.item))
        return resolvedItems.count
    }

    // MARK: - Liked Songs

    func isLiked(trackID: String) -> Bool {
        playlistStore.isLiked(trackID: trackID)
    }

    @discardableResult
    func toggleLiked(_ track: PlaybackTrack) -> LikedToggleResult {
        let result = playlistStore.toggleLiked(track.playlistEntry)
        refreshSnapshot(persistState: true)
        return result
    }

    @discardableResult
    func toggleLikedCurrentTrack() -> LikedToggleResult {
        guard let track = latestSnapshot.currentTrack else {
            return .playlistUnavailable
        }
        return toggleLiked(track)
    }

    // MARK: - Media Center

    func deliverLyricLine(_ line: String?) {
        player.updateNowPlayingSubtitle(line)
    }

    // MARK: - Cache

    func cachedItem(for trackID: String) -> PlayerItem? {
        queueState.itemCache[trackID]
    }

    // MARK: - UI Publishing

    func setUIPublishingSuspended(_ suspended: Bool) {
        guard isUIPublishingSuspended != suspended else {
            return
        }

        isUIPublishingSuspended = suspended
        player.setPeriodicTimeObserverSuspended(suspended)
        AppLog.info(self, "Playback UI publishing suspended=\(suspended)")

        if suspended {
            playbackStatusLogTimer?.invalidate()
            playbackStatusLogTimer = nil
            return
        }

        refreshSnapshot(
            currentTime: player.currentTime,
            duration: player.duration,
            persistState: true,
        )
    }

    // MARK: - Persistence

    func persistPlaybackState() {
        guard let session = makePersistedSession() else {
            sessionStore.clear()
            return
        }
        sessionStore.save(session)
    }

    @discardableResult
    func restorePersistedPlaybackIfNeeded(allowAutoPlay: Bool = false) async -> Bool {
        guard !restoreState.didAttemptPersistedRestore else {
            return latestSnapshot.currentTrack != nil
        }
        restoreState.didAttemptPersistedRestore = true

        guard let session = sessionStore.load(),
              !session.queue.isEmpty
        else {
            return false
        }

        var tracks: [PlaybackTrack] = []
        tracks.reserveCapacity(session.queue.count)
        for persistedTrack in session.queue {
            let localFileURL = persistedTrack.localRelativePath.map { paths.absoluteAudioURL(for: $0) }
            let artworkURL = await restoredArtworkURL(
                for: persistedTrack,
                localFileURL: localFileURL,
            )
            tracks.append(
                PlaybackTrack(
                    id: persistedTrack.id,
                    title: persistedTrack.title,
                    artistName: persistedTrack.artistName,
                    albumName: persistedTrack.albumName,
                    albumID: persistedTrack.albumID,
                    artworkURL: artworkURL,
                    durationInSeconds: persistedTrack.durationInSeconds,
                    localFileURL: localFileURL,
                ),
            )
        }
        let resolvedItems = await resolvePlayableItems(for: tracks)
        guard !resolvedItems.isEmpty else {
            sessionStore.clear()
            return false
        }

        let restoredTracks = resolvedItems.map(\.track)
        let restoredPlayerItems = resolvedItems.map(\.item)
        let restoredIndex = restoredCurrentIndex(for: resolvedItems, session: session)
        let restoredCurrentTrack = restoredTracks[restoredIndex]
        let restoredCurrentTime = restoredCurrentTrack.id == session.currentTrackID ? session.currentTime : 0

        queueState.currentSource = session.source
        queueState.trackLookup = Dictionary(uniqueKeysWithValues: resolvedItems.map { ($0.item.id, $0.track) })

        let restored = await player.restorePlayback(
            items: restoredPlayerItems,
            currentIndex: restoredIndex,
            shuffled: session.shuffled,
            repeatMode: session.repeatMode,
            currentTime: restoredCurrentTime,
            autoPlay: allowAutoPlay && session.shouldResumePlayback,
        )
        guard restored else {
            sessionStore.clear()
            return false
        }
        refreshSnapshot(
            currentTime: restoredCurrentTime,
            duration: player.duration,
            persistState: true,
        )
        return true
    }

    deinit {
        playbackStatusLogTimer?.invalidate()
        if let playlistsDidChangeObserver {
            NotificationCenter.default.removeObserver(playlistsDidChangeObserver)
        }
        if let routeChangeObserver {
            NotificationCenter.default.removeObserver(routeChangeObserver)
        }
    }
}
