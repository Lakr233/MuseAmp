//
//  NowPlayingRelaxedController+Playback.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import AmMusicKit
import AmMusicPlayerKit
import Combine
import ConfigurableKit
import LNPopupController
import UIKit

private struct RelaxedPresentationState: Equatable {
    let currentTrack: PlaybackTrack?
    let state: PlaybackState
    let duration: TimeInterval
    let isCurrentTrackLiked: Bool
    let outputDevice: PlaybackOutputDevice?

    init(snapshot: PlaybackSnapshot) {
        currentTrack = snapshot.currentTrack
        state = snapshot.state
        duration = snapshot.duration
        isCurrentTrackLiked = snapshot.isCurrentTrackLiked
        outputDevice = snapshot.outputDevice
    }
}

private struct RelaxedProgressState: Equatable {
    let trackID: String?
    let currentTime: TimeInterval
    let duration: TimeInterval

    init(snapshot: PlaybackSnapshot) {
        trackID = snapshot.currentTrack?.id
        currentTime = snapshot.currentTime
        duration = snapshot.duration
    }
}

// MARK: - Initial Presentation

extension NowPlayingRelaxedController {
    func applyInitialPlaybackPresentation() {
        let snapshot = environment.playbackController.snapshot
        currentPlaybackSnapshot = snapshot
        lastPresentedTrackID = snapshot.currentTrack?.id
        lastPresentedArtworkURL = snapshot.currentTrack?.artworkURL

        let presentation = controlIslandViewModel.apply(snapshot: snapshot)
        centerSectionView.configureTransport(
            with: presentation.content,
            animated: false,
        )
        refreshPlayingContent(animated: false)
        updateArtworkBackground(
            using: presentation.backgroundSource,
            animated: false,
        )
    }

    // MARK: - View Model Actions

    func bindViewModelActions() {
        controlIslandViewModel.bindActions(
            onFavorite: { [weak self] in
                guard let self else { return }
                _ = environment.playbackController.toggleLikedCurrentTrack()
                refreshControlIslandContent(animated: true)
            },
            onPrevious: { [weak self] in
                self?.previous()
            },
            onTogglePlayPause: { [weak self] in
                self?.togglePlayPause()
            },
            onNext: { [weak self] in
                self?.next()
            },
            onSeek: { [weak self] seconds in
                self?.seek(to: seconds)
            },
            onTitleTapped: { [weak self] in
                self?.navigateToCurrentAlbum()
            },
        )
    }

    // MARK: - Content Selector

    func bindContentSelector() {
        controlIslandViewModel.contentSelectorPublisher
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] selector in
                guard let self else { return }
                AppLog.info(
                    self,
                    "content selector changed selector=\(String(describing: selector)) trackID=\(currentPlaybackSnapshot.currentTrack?.id ?? "nil")",
                )
                switch selector {
                case .lyrics, .artwork:
                    switchRightPanel(to: .lyrics, animated: true)
                case .queue:
                    switchRightPanel(to: .queue, animated: true)
                }
                refreshControlIslandContent(animated: false)
                refreshPlayingContent(animated: false)
            }
            .store(in: &cancellables)
    }

    // MARK: - Queue Snapshot

    func bindQueueSnapshot() {
        environment.playbackController.$snapshot
            .removeDuplicates { lhs, rhs in
                lhs.queue == rhs.queue
                    && lhs.playerIndex == rhs.playerIndex
                    && lhs.repeatMode == rhs.repeatMode
            }
            .receive(on: DispatchQueue.main)
            .sink { @MainActor [weak self] snapshot in
                guard let self else { return }
                AppLog.info(
                    self,
                    "queue refresh received queueCount=\(snapshot.queue.count) historyCount=\(snapshot.history.count) upcomingCount=\(snapshot.upcoming.count) playerIndex=\(nowPlayingLogIndex(snapshot.playerIndex)) repeatMode=\(String(describing: snapshot.repeatMode))",
                )
                listSectionView.updateQueue(
                    queue: snapshot.queue,
                    playerIndex: snapshot.playerIndex,
                    repeatMode: snapshot.repeatMode,
                )
            }
            .store(in: &cancellables)
    }

    // MARK: - Playback Snapshot

    func bindPlaybackSnapshot() {
        let snapshotPublisher = environment.playbackController.$snapshot
            .receive(on: DispatchQueue.main)
            .share()

        snapshotPublisher
            .removeDuplicates { lhs, rhs in
                RelaxedPresentationState(snapshot: lhs) == RelaxedPresentationState(snapshot: rhs)
            }
            .sink { [weak self] snapshot in
                self?.applyPresentationSnapshot(snapshot)
            }
            .store(in: &cancellables)

        snapshotPublisher
            .removeDuplicates { lhs, rhs in
                RelaxedProgressState(snapshot: lhs) == RelaxedProgressState(snapshot: rhs)
            }
            .sink { [weak self] snapshot in
                self?.applyProgressSnapshot(snapshot)
            }
            .store(in: &cancellables)
    }

    // MARK: - Playback Time

    func bindPlaybackTime() {
        environment.playbackController.playbackTimeSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] currentTime, duration in
                guard let self, !isInterfaceSuspended else { return }
                let updatedSnapshot = currentPlaybackSnapshot.withTime(currentTime, duration: duration)
                currentPlaybackSnapshot = updatedSnapshot

                let content = controlIslandViewModel.content(for: updatedSnapshot)
                centerSectionView.configureTransport(with: content, animated: false)

                guard currentRightPanel == .lyrics else { return }
                guard let trackID = updatedSnapshot.currentTrack?.id else {
                    lyricSectionView.updateLyrics(text: nil, isLoading: false, currentTime: currentTime)
                    return
                }
                let lyricsText = lyricsCache[trackID]
                lyricSectionView.updateLyrics(
                    text: lyricsText,
                    isLoading: lyricsText == nil && lyricsLoadingTrackID == trackID,
                    currentTime: currentTime,
                )
            }
            .store(in: &cancellables)
    }

    // MARK: - Presentation Apply

    func applyPresentationSnapshot(_ snapshot: PlaybackSnapshot) {
        currentPlaybackSnapshot = snapshot
        guard !isInterfaceSuspended else { return }

        let previousTrackID = lastPresentedTrackID
        let previousArtworkURL = lastPresentedArtworkURL
        let nextTrackID = snapshot.currentTrack?.id
        let nextArtworkURL = snapshot.currentTrack?.artworkURL
        let trackDidChange = previousTrackID != nextTrackID
        let artworkDidChange = previousArtworkURL != nextArtworkURL

        lastPresentedTrackID = nextTrackID
        lastPresentedArtworkURL = nextArtworkURL

        if trackDidChange,
           nextTrackID != lyricsTransientFailureTrackID
        {
            lyricsTransientFailureTrackID = nil
        }

        let presentation = controlIslandViewModel.apply(snapshot: snapshot)
        centerSectionView.configureTransport(
            with: presentation.content,
            animated: presentation.shouldAnimateTransition || presentation.shouldAnimatePlaybackStateChange,
        )

        if trackDidChange {
            if let nextTrackID {
                loadLyrics(for: nextTrackID)
            } else {
                lyricsTask?.cancel()
                lyricsTask = nil
                lyricsLoadingTrackID = nil
                lyricSectionView.updateLyrics(text: nil, isLoading: false, currentTime: snapshot.currentTime)
            }
        }

        guard trackDidChange || artworkDidChange else { return }

        refreshPlayingContent(animated: presentation.shouldAnimateTransition)
        updateArtworkBackground(
            using: presentation.backgroundSource,
            animated: presentation.shouldAnimateTransition,
        )

        if presentation.shouldAnimateTransition {
            view.setNeedsLayout()
            InterfaceAnimate.springAnimate(
                duration: 0.42,
                dampingRatio: 0.9,
                initialVelocity: 0.8,
            ) {
                self.view.layoutIfNeeded()
            }
        }
    }

    func applyProgressSnapshot(_ snapshot: PlaybackSnapshot) {
        currentPlaybackSnapshot = snapshot
        guard !isInterfaceSuspended else { return }

        let content = controlIslandViewModel.content(for: snapshot)
        centerSectionView.configureTransport(with: content, animated: false)

        guard currentRightPanel == .lyrics else { return }
        guard let trackID = snapshot.currentTrack?.id else {
            lyricSectionView.updateLyrics(text: nil, isLoading: false, currentTime: snapshot.currentTime)
            return
        }

        let lyricsText = lyricsCache[trackID]
        lyricSectionView.updateLyrics(
            text: lyricsText,
            isLoading: lyricsText == nil && lyricsLoadingTrackID == trackID,
            currentTime: snapshot.currentTime,
        )
    }

    // MARK: - Refresh

    func refreshControlIslandContent(animated: Bool) {
        let snapshot = currentPlaybackSnapshot
        let presentation = controlIslandViewModel.apply(snapshot: snapshot)
        centerSectionView.configureTransport(
            with: presentation.content,
            animated: animated,
        )
    }

    func refreshPlayingContent(animated: Bool) {
        let snapshot = currentPlaybackSnapshot
        let currentTrackID = snapshot.currentTrack?.id ?? "nil"
        let artworkDescription = nowPlayingLogURLDescription(snapshot.currentTrack?.artworkURL)

        AppLog.info(
            self,
            "refreshPlayingContent panel=\(String(describing: currentRightPanel)) trackID=\(currentTrackID) artwork=\(artworkDescription) animated=\(animated)",
        )

        centerSectionView.updateArtwork(url: snapshot.currentTrack?.artworkURL)

        guard let trackID = snapshot.currentTrack?.id else {
            lyricsTask?.cancel()
            lyricsLoadingTrackID = nil
            lyricSectionView.updateLyrics(text: nil, isLoading: false, currentTime: snapshot.currentTime)
            return
        }

        if let lyrics = lyricsCache[trackID] {
            lyricSectionView.updateLyrics(
                text: lyrics.isEmpty ? nil : lyrics,
                isLoading: false,
                currentTime: snapshot.currentTime,
            )
        } else {
            lyricSectionView.updateLyrics(
                text: nil,
                isLoading: lyricsLoadingTrackID == trackID,
                currentTime: snapshot.currentTime,
            )
        }

        loadLyrics(for: trackID)
    }

    // MARK: - Lyrics Loading

    func processedLyrics(_ text: String) -> String {
        guard !text.isEmpty, AppPreferences.isLyricsAutoConvertChineseEnabled else {
            return text
        }
        return LyricsChineseScriptConverter.convertToSystemScript(text)
    }

    func cacheLyrics(_ text: String, for trackID: String) {
        lyricsRawCache[trackID] = text
        lyricsCache[trackID] = processedLyrics(text)
    }

    func reprocessAllCachedLyrics() {
        for (trackID, raw) in lyricsRawCache {
            lyricsCache[trackID] = processedLyrics(raw)
        }
        guard let trackID = currentPlaybackSnapshot.currentTrack?.id,
              let lyrics = lyricsCache[trackID]
        else { return }
        lyricSectionView.updateLyrics(
            text: lyrics.isEmpty ? nil : lyrics,
            isLoading: false,
            currentTime: currentPlaybackSnapshot.currentTime,
        )
    }

    func loadLyrics(for trackID: String) {
        if let lyrics = lyricsCache[trackID] {
            AppLog.info(
                self,
                "loadLyrics refresh source=memory-cache trackID=\(trackID) \(nowPlayingLogTextSummary(lyrics))",
            )
            lyricsLoadingTrackID = nil
            if lyricsTransientFailureTrackID == trackID {
                lyricsTransientFailureTrackID = nil
            }
            lyricSectionView.updateLyrics(
                text: lyrics.isEmpty ? nil : lyrics,
                isLoading: false,
                currentTime: currentPlaybackSnapshot.currentTime,
            )
            return
        }

        if let storedLyrics = environment.lyricsService.cachedLyrics(for: trackID) {
            AppLog.info(
                self,
                "loadLyrics refresh source=offline-cache trackID=\(trackID) \(nowPlayingLogTextSummary(storedLyrics))",
            )
            lyricsLoadingTrackID = nil
            if lyricsTransientFailureTrackID == trackID {
                lyricsTransientFailureTrackID = nil
            }
            cacheLyrics(storedLyrics, for: trackID)
            let cached = lyricsCache[trackID] ?? storedLyrics
            lyricSectionView.updateLyrics(
                text: cached.isEmpty ? nil : cached,
                isLoading: false,
                currentTime: currentPlaybackSnapshot.currentTime,
            )
            return
        }

        if lyricsTransientFailureTrackID == trackID {
            AppLog.info(
                self,
                "loadLyrics refresh source=transient-failure trackID=\(trackID)",
            )
            lyricsLoadingTrackID = nil
            lyricSectionView.updateLyrics(
                text: nil,
                isLoading: false,
                currentTime: currentPlaybackSnapshot.currentTime,
            )
            return
        }

        if lyricsLoadingTrackID == trackID {
            AppLog.verbose(
                self,
                "loadLyrics refresh source=in-flight trackID=\(trackID)",
            )
            lyricSectionView.updateLyrics(
                text: nil,
                isLoading: true,
                currentTime: currentPlaybackSnapshot.currentTime,
            )
            return
        }

        if let pendingTrackID = lyricsLoadingTrackID,
           pendingTrackID != trackID
        {
            AppLog.info(
                self,
                "loadLyrics refresh cancel pendingTrackID=\(pendingTrackID) nextTrackID=\(trackID)",
            )
        }
        lyricsTask?.cancel()
        lyricsLoadingTrackID = trackID
        AppLog.info(self, "loadLyrics refresh source=network-start trackID=\(trackID)")
        lyricSectionView.updateLyrics(
            text: nil,
            isLoading: true,
            currentTime: currentPlaybackSnapshot.currentTime,
        )

        lyricsTask = Task { [weak self] in
            guard let self else { return }
            do {
                let lyrics = try await environment.lyricsService.fetchLyrics(for: trackID)
                guard !Task.isCancelled else { return }
                let normalizedLyrics = lyrics.trimmingCharacters(in: .whitespacesAndNewlines)
                environment.lyricsService.persistLyricsIfDownloaded(normalizedLyrics, for: trackID)

                await MainActor.run { [weak self] in
                    guard let self else { return }
                    lyricsLoadingTrackID = nil
                    if lyricsTransientFailureTrackID == trackID {
                        lyricsTransientFailureTrackID = nil
                    }
                    cacheLyrics(normalizedLyrics, for: trackID)
                    AppLog.info(
                        self,
                        "loadLyrics refresh source=network-success trackID=\(trackID) \(nowPlayingLogTextSummary(normalizedLyrics))",
                    )
                    guard currentPlaybackSnapshot.currentTrack?.id == trackID else { return }
                    let cached = lyricsCache[trackID] ?? normalizedLyrics
                    lyricSectionView.updateLyrics(
                        text: cached.isEmpty ? nil : cached,
                        isLoading: false,
                        currentTime: currentPlaybackSnapshot.currentTime,
                    )
                }
            } catch {
                guard !Task.isCancelled else { return }
                let shouldCacheUnavailableResult = shouldCacheUnavailableLyricsResult(for: error)
                if shouldCacheUnavailableResult {
                    environment.lyricsService.persistLyricsIfDownloaded("", for: trackID)
                }

                await MainActor.run { [weak self] in
                    guard let self else { return }
                    lyricsLoadingTrackID = nil
                    if shouldCacheUnavailableResult {
                        if lyricsTransientFailureTrackID == trackID {
                            lyricsTransientFailureTrackID = nil
                        }
                        lyricsRawCache[trackID] = ""
                        lyricsCache[trackID] = ""
                    } else {
                        lyricsTransientFailureTrackID = trackID
                    }
                    guard currentPlaybackSnapshot.currentTrack?.id == trackID else { return }
                    lyricSectionView.updateLyrics(
                        text: nil,
                        isLoading: false,
                        currentTime: currentPlaybackSnapshot.currentTime,
                    )
                    if shouldCacheUnavailableResult {
                        AppLog.info(self, "loadLyrics refresh source=network-unavailable trackID=\(trackID)")
                    } else {
                        AppLog.error(self, "loadLyrics refresh source=network-failure trackID=\(trackID) error=\(error)")
                    }
                }
            }
        }
    }

    // MARK: - Preference Bindings

    func bindLyricsChineseConvertPreference() {
        ConfigurableKit.publisher(
            forKey: AppPreferences.lyricsAutoConvertChineseKey,
            type: Bool.self,
        )
        .dropFirst()
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
            self?.reprocessAllCachedLyrics()
        }
        .store(in: &cancellables)
    }

    func bindCleanSongTitlePreference() {
        ConfigurableKit.publisher(
            forKey: AppPreferences.cleanSongTitleKey, type: Bool.self,
        )
        .dropFirst()
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
            guard let self else { return }
            let snapshot = environment.playbackController.snapshot
            let presentation = controlIslandViewModel.apply(snapshot: snapshot)
            centerSectionView.configureTransport(
                with: presentation.content,
                animated: false,
            )
        }
        .store(in: &cancellables)
    }

    // MARK: - Queue Actions

    func bindQueueSectionActions() {
        listSectionView.onToggleShuffle = { [weak self] in
            self?.shuffleQueueOnce()
        }

        listSectionView.onSelectQueueTrack = { [weak self] selection in
            guard let self else { return }
            switch selection {
            case let .queue(index):
                environment.playbackController.skipToQueueTrack(at: index)
            }
        }

        listSectionView.onRemoveQueueTrack = { [weak self] queueIndex in
            self?.environment.playbackController.removeFromQueue(at: queueIndex)
        }

        listSectionView.onRestartCurrentTrack = { [weak self] in
            self?.environment.playbackController.restartCurrentTrack()
        }

        listSectionView.onPlayFromHere = { [weak self] queueIndex in
            self?.environment.playbackController.skipToQueueTrack(at: queueIndex)
        }

        listSectionView.onPlayNext = { [weak self] track in
            guard let self else { return }
            Task {
                _ = await self.environment.playbackController.playNext([track])
            }
        }

        listSectionView.onCycleRepeatMode = { [weak self] in
            guard let self else { return }
            let nextMode: RepeatMode = switch currentPlaybackSnapshot.repeatMode {
            case .off:
                .queue
            case .queue:
                .track
            case .track:
                .off
            }
            setRepeatMode(nextMode)
        }
    }

    func shuffleQueueOnce() {
        guard !currentPlaybackSnapshot.upcoming.isEmpty else { return }

        queueShuffleFeedbackTask?.cancel()
        isQueueShuffleFeedbackActive = true
        listSectionView.setShuffleFeedbackActive(true)

        Task { [weak self] in
            await self?.environment.playbackController.shuffleUpcomingQueue()
        }

        queueShuffleFeedbackTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled, let self else { return }
            isQueueShuffleFeedbackActive = false
            listSectionView.setShuffleFeedbackActive(false)
        }
    }

    // MARK: - Title Tap Navigation

    func navigateToCurrentAlbum() {
        let track = environment.playbackController.snapshot.currentTrack
        guard let track else { return }
        guard let mainController = view.window?.rootViewController as? MainController else { return }

        popupPresentationContainer?.closePopup(animated: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let nav: UINavigationController? = if mainController.currentLayoutMode == .compact {
                mainController.compactTabBarController.selectedViewController as? UINavigationController
            } else {
                mainController.activeContentNavigationController
            }
            guard let nav else { return }
            let helper = AlbumNavigationHelper(
                environment: mainController.environment,
                viewController: nav.topViewController,
            )
            helper.pushAlbumDetail(
                songID: track.id,
                albumID: track.albumID,
                albumName: track.albumName ?? "",
                artistName: track.artistName,
            )
        }
    }
}
