//
//  NowPlayingCompactController+Playback.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import AmMusicPlayerKit
import Combine
import DominantColors
import Kingfisher
import LNPopupController
import LRUCache
import UIKit

private struct NowPlayingPresentationState: Equatable {
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

private struct NowPlayingProgressState: Equatable {
    let trackID: String?
    let currentTime: TimeInterval
    let duration: TimeInterval

    init(snapshot: PlaybackSnapshot) {
        trackID = snapshot.currentTrack?.id
        currentTime = snapshot.currentTime
        duration = snapshot.duration
    }
}

extension NowPlayingCompactController {
    func applyInitialPlaybackPresentation() {
        let snapshot = environment.playbackController.snapshot
        currentPlaybackSnapshot = snapshot
        lastPresentedTrackID = snapshot.currentTrack?.id
        lastPresentedArtworkURL = snapshot.currentTrack?.artworkURL

        let presentation = controlIslandViewModel.apply(snapshot: snapshot)
        pageViewController.configureTransport(
            with: presentation.content,
            animated: false,
        )
        updateTransportLyricLine(for: snapshot)
        refreshPlayingContent(animated: false)
        updateArtworkBackground(
            using: presentation.backgroundSource,
            animated: false,
        )
    }

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
                updatePopupCloseButtonAppearance(for: selector)
                pageViewController.setSelector(selector, animated: true)
                refreshControlIslandContent(animated: false)
                refreshPlayingContent(animated: false)
            }
            .store(in: &cancellables)
    }

    func bindQueueSnapshot() {
        environment.playbackController.$snapshot
            .removeDuplicates { lhs, rhs in
                lhs.queue == rhs.queue
                    && lhs.playerIndex == rhs.playerIndex
                    && lhs.repeatMode == rhs.repeatMode
            }
            .receive(on: DispatchQueue.main)
            .sink { @MainActor [weak self] snapshot in
                guard let self else {
                    return
                }

                AppLog.info(
                    self,
                    "queue refresh received queueCount=\(snapshot.queue.count) historyCount=\(snapshot.history.count) upcomingCount=\(snapshot.upcoming.count) playerIndex=\(nowPlayingLogIndex(snapshot.playerIndex)) repeatMode=\(String(describing: snapshot.repeatMode))",
                )
                pageViewController.updateQueue(
                    queue: snapshot.queue,
                    playerIndex: snapshot.playerIndex,
                    repeatMode: snapshot.repeatMode,
                    animatingDifferences: true,
                )
            }
            .store(in: &cancellables)
    }

    func bindPlaybackSnapshot() {
        let snapshotPublisher = environment.playbackController.$snapshot
            .receive(on: DispatchQueue.main)
            .share()

        snapshotPublisher
            .removeDuplicates { lhs, rhs in
                NowPlayingPresentationState(snapshot: lhs) == NowPlayingPresentationState(snapshot: rhs)
            }
            .sink { [weak self] snapshot in
                self?.applyPresentationSnapshot(snapshot)
            }
            .store(in: &cancellables)

        snapshotPublisher
            .removeDuplicates { lhs, rhs in
                NowPlayingProgressState(snapshot: lhs) == NowPlayingProgressState(snapshot: rhs)
            }
            .sink { [weak self] snapshot in
                self?.applyProgressSnapshot(snapshot)
            }
            .store(in: &cancellables)
    }

    func bindPlaybackTime() {
        environment.playbackController.playbackTimeSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] currentTime, duration in
                guard let self, !isInterfaceSuspended else { return }
                let updatedSnapshot = currentPlaybackSnapshot.withTime(currentTime, duration: duration)
                currentPlaybackSnapshot = updatedSnapshot

                let content = controlIslandViewModel.content(for: updatedSnapshot)
                pageViewController.configureTransport(with: content, animated: false)

                updateTransportLyricLine(for: updatedSnapshot)

                guard controlIslandViewModel.selectedContentSelector == .lyrics else { return }
                guard let trackID = updatedSnapshot.currentTrack?.id else {
                    pageViewController.updateLyrics(text: nil, isLoading: false, currentTime: currentTime)
                    return
                }
                let lyricsText = lyricsCache[trackID]
                pageViewController.updateLyrics(
                    text: lyricsText,
                    isLoading: lyricsText == nil && lyricsLoadingTrackID == trackID,
                    currentTime: currentTime,
                )
            }
            .store(in: &cancellables)
    }

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
        pageViewController.configureTransport(
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
                pageViewController.updateLyrics(text: nil, isLoading: false, currentTime: snapshot.currentTime)
            }
        }
        guard trackDidChange || artworkDidChange else {
            return
        }

        refreshPlayingContent(animated: presentation.shouldAnimateTransition)
        updateArtworkBackground(
            using: presentation.backgroundSource,
            animated: presentation.shouldAnimateTransition,
        )
    }

    func applyProgressSnapshot(_ snapshot: PlaybackSnapshot) {
        currentPlaybackSnapshot = snapshot

        guard !isInterfaceSuspended else { return }

        let content = controlIslandViewModel.content(for: snapshot)
        pageViewController.configureTransport(with: content, animated: false)

        updateTransportLyricLine(for: snapshot)

        guard controlIslandViewModel.selectedContentSelector == .lyrics else {
            return
        }

        guard let trackID = snapshot.currentTrack?.id else {
            pageViewController.updateLyrics(text: nil, isLoading: false, currentTime: snapshot.currentTime)
            return
        }

        let lyricsText = lyricsCache[trackID]
        pageViewController.updateLyrics(
            text: lyricsText,
            isLoading: lyricsText == nil && lyricsLoadingTrackID == trackID,
            currentTime: snapshot.currentTime,
        )
    }

    func updateTransportLyricLine(for snapshot: PlaybackSnapshot) {
        guard let trackID = snapshot.currentTrack?.id,
              let lyricsText = lyricsCache[trackID],
              !lyricsText.isEmpty
        else {
            pageViewController.updateCurrentLyricLine(nil)
            return
        }

        let timeline = LRCLyricsTimeline(lrc: lyricsText)
        guard !timeline.lines.isEmpty,
              let progress = timeline.progress(at: snapshot.currentTime)
        else {
            pageViewController.updateCurrentLyricLine(nil)
            return
        }

        pageViewController.updateCurrentLyricLine(progress.line.text)
    }

    func refreshControlIslandContent(animated: Bool) {
        let snapshot = currentPlaybackSnapshot
        let presentation = controlIslandViewModel.apply(snapshot: snapshot)
        pageViewController.configureTransport(
            with: presentation.content,
            animated: animated,
        )
    }

    func refreshPlayingContent(animated: Bool) {
        let snapshot = currentPlaybackSnapshot
        let selector = controlIslandViewModel.selectedContentSelector
        let currentTrackID = snapshot.currentTrack?.id ?? "nil"
        let artworkDescription = nowPlayingLogURLDescription(snapshot.currentTrack?.artworkURL)
        let lyricsState = if let trackID = snapshot.currentTrack?.id,
                             let cachedLyrics = lyricsCache[trackID]
        {
            "cached[\(nowPlayingLogTextSummary(cachedLyrics))]"
        } else if let loadingTrackID = lyricsLoadingTrackID {
            "loading[\(loadingTrackID)]"
        } else {
            "idle"
        }

        AppLog.info(
            self,
            "refreshPlayingContent selector=\(String(describing: selector)) trackID=\(currentTrackID) artwork=\(artworkDescription) lyrics=\(lyricsState) animated=\(animated)",
        )

        pageViewController.setSelector(selector, animated: animated)
        pageViewController.updateArtwork(url: snapshot.currentTrack?.artworkURL)

        guard selector == .lyrics else {
            return
        }

        guard let trackID = snapshot.currentTrack?.id else {
            lyricsTask?.cancel()
            lyricsLoadingTrackID = nil
            pageViewController.updateLyrics(text: nil, isLoading: false, currentTime: snapshot.currentTime)
            return
        }

        if let lyrics = lyricsCache[trackID] {
            pageViewController.updateLyrics(
                text: lyrics.isEmpty ? nil : lyrics,
                isLoading: false,
                currentTime: snapshot.currentTime,
            )
        } else {
            pageViewController.updateLyrics(
                text: nil,
                isLoading: lyricsLoadingTrackID == trackID,
                currentTime: snapshot.currentTime,
            )
        }

        loadLyrics(for: trackID)
    }

    func applyIdleBackgroundIfNeeded(animated _: Bool) {
        backgroundView.apply(colors: idleBackgroundColors)
        lastBackgroundSource = .idle
    }

    static func makeIdleBackgroundColors() -> [UIColor] {
        [
            UIColor(white: 0.45, alpha: 1),
            UIColor(white: 0.50, alpha: 1),
            UIColor(white: 0.52, alpha: 1),
            UIColor(white: 0.48, alpha: 1),
        ]
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

extension NowPlayingCompactController {
    func updateArtworkBackground(
        using backgroundSource: NowPlayingControlIslandViewModel.BackgroundSource,
        animated: Bool,
    ) {
        switch (lastBackgroundSource, backgroundSource) {
        case let (.artwork(previousURL), .artwork(currentURL)):
            if previousURL == currentURL,
               artworkPaletteCache.value(forKey: currentURL.absoluteString) != nil
            {
                return
            }
        case (.idle, .idle):
            return
        default:
            break
        }
        lastBackgroundSource = backgroundSource
        artworkPaletteTask?.cancel()

        switch backgroundSource {
        case .idle:
            applyIdleBackgroundIfNeeded(animated: animated)
        case let .artwork(url):
            if let cachedColors = artworkPaletteCache.value(forKey: url.absoluteString) {
                backgroundView.apply(colors: cachedColors)
                return
            }

            artworkPaletteTask = Task { [weak self] in
                guard let self else { return }
                let colors = await paletteColors(for: url)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard self.lastBackgroundSource == backgroundSource else { return }
                    if let colors {
                        self.artworkPaletteCache.setValue(colors, forKey: url.absoluteString)
                        self.backgroundView.apply(colors: colors)
                    } else {
                        self.backgroundView.apply(colors: self.idleBackgroundColors)
                    }
                }
            }
        }
    }

    func paletteColors(for artworkURL: URL) async -> [UIColor]? {
        guard let image = await retrieveArtworkImage(from: artworkURL) else {
            return nil
        }
        return await extractPalette(from: image)
    }

    func updateArtworkBackgroundFromDisplayedArtwork(url: URL, image: UIImage) {
        guard case let .artwork(currentURL) = lastBackgroundSource,
              currentURL == url
        else {
            return
        }

        if let cachedColors = artworkPaletteCache.value(forKey: url.absoluteString) {
            backgroundView.apply(colors: cachedColors)
            return
        }

        artworkPaletteTask?.cancel()
        artworkPaletteTask = Task { [weak self] in
            guard let self else { return }
            let colors = await extractPalette(from: image)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard self.currentPlaybackSnapshot.currentTrack?.artworkURL == url
                else {
                    return
                }

                guard let colors else { return }
                self.artworkPaletteCache.setValue(colors, forKey: url.absoluteString)
                self.backgroundView.apply(colors: colors)
            }
        }
    }

    func retrieveArtworkImage(from artworkURL: URL) async -> UIImage? {
        if artworkURL.isFileURL {
            return UIImage(contentsOfFile: artworkURL.path)
        }

        return await withCheckedContinuation { continuation in
            KingfisherManager.shared.retrieveImage(with: artworkURL) { result in
                switch result {
                case let .success(value):
                    continuation.resume(returning: value.image)
                case .failure:
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    func extractPalette(from image: UIImage) async -> [UIColor]? {
        let imageData = image.pngData() ?? image.jpegData(compressionQuality: 1)
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let imageData,
                      let decodedImage = UIImage(data: imageData)
                else {
                    continuation.resume(returning: nil)
                    return
                }

                let extracted = (try? DominantColors.dominantColors(
                    uiImage: decodedImage,
                    quality: .best,
                    maxCount: 4,
                    options: [.excludeBlack, .excludeWhite, .excludeGray],
                )) ?? []

                continuation.resume(returning: extracted)
            }
        }
    }
}
