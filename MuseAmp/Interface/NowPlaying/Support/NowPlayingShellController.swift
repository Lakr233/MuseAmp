//
//  NowPlayingShellController.swift
//  MuseAmp
//
//  Created by @Lakr233 on 2026/04/11.
//

import Combine
import ConfigurableKit
import MuseAmpPlayerKit
import UIKit

@MainActor
protocol NowPlayingShellController: AnyObject {
    var environment: AppEnvironment { get }
    var controlIslandViewModel: NowPlayingControlIslandViewModel { get }
    var currentPlaybackSnapshot: PlaybackSnapshot { get set }
    var cancellables: Set<AnyCancellable> { get set }
}

@MainActor
protocol NowPlayingQueueActionPresenting: AnyObject {
    var onToggleShuffle: () -> Void { get set }
    var onSelectQueueTrack: (NowPlayingQueueTrackSelection) -> Void { get set }
    var onRemoveQueueTrack: (Int) -> Void { get set }
    var onRestartCurrentTrack: () -> Void { get set }
    var onPlayFromHere: (Int) -> Void { get set }
    var onPlayNext: (Int) -> Void { get set }
    var onCycleRepeatMode: () -> Void { get set }
}

extension NowPlayingListSectionView: NowPlayingQueueActionPresenting {}

extension NowPlayingCompactPageController: NowPlayingQueueActionPresenting {
    var onToggleShuffle: () -> Void {
        get { onToggleQueueShuffle }
        set { onToggleQueueShuffle = newValue }
    }

    var onCycleRepeatMode: () -> Void {
        get { onCycleQueueRepeatMode }
        set { onCycleQueueRepeatMode = newValue }
    }
}

@MainActor
protocol NowPlayingQueueShellController: NowPlayingPlaybackShellController {
    var queueShuffleFeedbackCoordinator: NowPlayingQueueShuffleFeedbackCoordinator { get }

    func setRepeatMode(_ mode: RepeatMode)
    func installQueueActionHandlers(
        onToggleShuffle: @escaping () -> Void,
        onSelectQueueTrack: @escaping (NowPlayingQueueTrackSelection) -> Void,
        onRemoveQueueTrack: @escaping (Int) -> Void,
        onRestartCurrentTrack: @escaping () -> Void,
        onPlayFromHere: @escaping (Int) -> Void,
        onPlayNext: @escaping (Int) -> Void,
        onCycleRepeatMode: @escaping () -> Void,
    )
}

extension NowPlayingQueueShellController where Self: UIViewController {
    func setRepeatMode(_ mode: RepeatMode) {
        environment.playbackController.setRepeatMode(mode)
    }

    func configureQueueActionPresenter(
        _ view: some NowPlayingQueueActionPresenting,
        onToggleShuffle: @escaping () -> Void,
        onSelectQueueTrack: @escaping (NowPlayingQueueTrackSelection) -> Void,
        onRemoveQueueTrack: @escaping (Int) -> Void,
        onRestartCurrentTrack: @escaping () -> Void,
        onPlayFromHere: @escaping (Int) -> Void,
        onPlayNext: @escaping (Int) -> Void,
        onCycleRepeatMode: @escaping () -> Void,
    ) {
        view.onToggleShuffle = onToggleShuffle
        view.onSelectQueueTrack = onSelectQueueTrack
        view.onRemoveQueueTrack = onRemoveQueueTrack
        view.onRestartCurrentTrack = onRestartCurrentTrack
        view.onPlayFromHere = onPlayFromHere
        view.onPlayNext = onPlayNext
        view.onCycleRepeatMode = onCycleRepeatMode
    }

    func bindQueueSectionActions() {
        installQueueActionHandlers(
            onToggleShuffle: { [weak self] in
                self?.shuffleQueueOnce()
            },
            onSelectQueueTrack: { [weak self] selection in
                guard let self else { return }
                switch selection {
                case let .queue(index):
                    environment.playbackController.skipToQueueTrack(at: index)
                }
            },
            onRemoveQueueTrack: { [weak self] queueIndex in
                self?.environment.playbackController.removeFromQueue(at: queueIndex)
            },
            onRestartCurrentTrack: { [weak self] in
                self?.environment.playbackController.restartCurrentTrack()
            },
            onPlayFromHere: { [weak self] queueIndex in
                self?.environment.playbackController.skipToQueueTrack(at: queueIndex)
            },
            onPlayNext: { [weak self] queueIndex in
                guard let self else { return }
                guard currentPlaybackSnapshot.queue.indices.contains(queueIndex) else {
                    return
                }
                let track = currentPlaybackSnapshot.queue[queueIndex]
                Task {
                    _ = await self.environment.playbackController.playNext([track])
                }
            },
            onCycleRepeatMode: { [weak self] in
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
            },
        )
    }

    func shuffleQueueOnce() {
        guard !currentPlaybackSnapshot.upcoming.isEmpty else { return }

        queueShuffleFeedbackCoordinator.performShuffle { [weak self] in
            await self?.environment.playbackController.shuffleUpcomingQueue()
        }
    }
}

extension NowPlayingPlaybackShellController where Self: UIViewController {
    func bindCleanSongTitlePreference() {
        ConfigurableKit.publisher(
            forKey: AppPreferences.cleanSongTitleKey, type: Bool.self,
        )
        .dropFirst()
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
            guard let self else { return }

            let snapshot = environment.playbackController.snapshot
            currentPlaybackSnapshot = snapshot

            AppLog.info(
                self,
                "clean-song-title preference changed queueCount=\(snapshot.queue.count) playerIndex=\(nowPlayingLogIndex(snapshot.playerIndex))",
            )

            controlIslandViewModel.apply(snapshot: snapshot)
            updateQueuePresentation(
                queue: snapshot.queue,
                playerIndex: snapshot.playerIndex,
                repeatMode: snapshot.repeatMode,
            )
        }
        .store(in: &cancellables)
    }

    func makeShowLyricsAction() -> UIAction {
        UIAction(
            title: String(localized: "Show Lyrics"),
            image: UIImage(systemName: "text.quote"),
        ) { [weak self] _ in
            self?.controlIslandViewModel.setContentSelector(.lyrics)
        }
    }

    func makeShowPlaybackQueueAction() -> UIAction {
        UIAction(
            title: String(localized: "Show Playback Queue"),
            image: UIImage(systemName: "list.bullet"),
        ) { [weak self] _ in
            self?.controlIslandViewModel.setContentSelector(.queue)
        }
    }
}
