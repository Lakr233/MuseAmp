//
//  NowPlayingPlaybackShellController.swift
//  MuseAmp
//
//  Created by @Lakr233 on 2026/04/11.
//

import Combine
import MuseAmpPlayerKit
import UIKit

private struct NowPlayingPresentationState: Equatable {
    let currentTrack: PlaybackTrack?
    let state: PlaybackState
    let isCurrentTrackLiked: Bool
    let outputDevice: PlaybackOutputDevice?

    init(snapshot: PlaybackSnapshot) {
        currentTrack = snapshot.currentTrack
        state = snapshot.state
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

@MainActor
protocol NowPlayingPlaybackShellController: NowPlayingShellController {
    var artworkBackgroundCoordinator: NowPlayingArtworkBackgroundCoordinator { get }
    var lastPresentedTrackID: String? { get set }
    var lastPresentedArtworkURL: URL? { get set }
    var isInterfaceSuspended: Bool { get }

    func handleContentSelectorChange(_ selector: NowPlayingControlIslandViewModel.ContentSelector)
    func updateQueuePresentation(queue: [PlaybackTrack], playerIndex: Int?, repeatMode: RepeatMode)
    func applySupplementalPlaybackProgress(for snapshot: PlaybackSnapshot)
    func refreshPlayingContent(animated: Bool)
    func animateTrackTransitionIfNeeded(shouldAnimate: Bool)
}

extension NowPlayingPlaybackShellController where Self: UIViewController {
    func animateTrackTransitionIfNeeded(shouldAnimate _: Bool) {}

    func applyInitialPlaybackPresentation() {
        let snapshot = environment.playbackController.snapshot
        currentPlaybackSnapshot = snapshot
        lastPresentedTrackID = snapshot.currentTrack?.id
        lastPresentedArtworkURL = snapshot.currentTrack?.artworkURL

        let presentation = controlIslandViewModel.apply(snapshot: snapshot)
        applySupplementalPlaybackProgress(for: snapshot)
        refreshPlayingContent(animated: false)
        artworkBackgroundCoordinator.update(
            using: presentation.backgroundSource,
            animated: false,
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
                handleContentSelectorChange(selector)
                refreshControlIslandContent()
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
                guard let self else { return }
                AppLog.info(
                    self,
                    "queue refresh received queueCount=\(snapshot.queue.count) historyCount=\(snapshot.history.count) upcomingCount=\(snapshot.upcoming.count) playerIndex=\(nowPlayingLogIndex(snapshot.playerIndex)) repeatMode=\(String(describing: snapshot.repeatMode))",
                )
                updateQueuePresentation(
                    queue: snapshot.queue,
                    playerIndex: snapshot.playerIndex,
                    repeatMode: snapshot.repeatMode,
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
                applySupplementalPlaybackProgress(for: updatedSnapshot)
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

        let presentation = controlIslandViewModel.apply(snapshot: snapshot)

        guard trackDidChange || artworkDidChange else { return }

        refreshPlayingContent(animated: presentation.shouldAnimateTransition)
        artworkBackgroundCoordinator.update(
            using: presentation.backgroundSource,
            animated: presentation.shouldAnimateTransition,
        )
        animateTrackTransitionIfNeeded(shouldAnimate: presentation.shouldAnimateTransition)
    }

    func applyProgressSnapshot(_ snapshot: PlaybackSnapshot) {
        currentPlaybackSnapshot = snapshot

        guard !isInterfaceSuspended else { return }

        applySupplementalPlaybackProgress(for: snapshot)
    }

    func refreshControlIslandContent() {
        controlIslandViewModel.apply(snapshot: currentPlaybackSnapshot)
    }
}
