//
//  TVNowPlayingController.swift
//  MuseAmpTV
//
//  Hosts the tvOS Now Playing page: artwork + simplified transport on the
//  left, read-only lyrics on the right.
//

import Combine
import MuseAmpPlayerKit
import SnapKit
import UIKit

@MainActor
final class TVNowPlayingController: UIViewController {
    private let context: TVAppContext
    private let contentView = TVNowPlayingView()
    private lazy var lyricsCoordinator = TVNowPlayingLyricsCoordinator(
        lyricsService: context.lyricsService,
        shouldApplyLoadedLyrics: { [weak self] trackID in
            guard let currentID = self?.latestSnapshot.currentTrack?.id else { return false }
            return TVNowPlayingController.catalogTrackID(from: currentID) == trackID
        },
        updateLyricsView: { [weak self] text, isLoading in
            guard let self else { return }
            contentView.lyricsView.update(
                text: text,
                isLoading: isLoading,
                currentTime: latestSnapshot.currentTime,
            )
        },
    )

    private var cancellables: Set<AnyCancellable> = []
    private var latestSnapshot = PlaybackSnapshot.empty
    private var lastPresentedTrackID: String?
    private var scrubCommitCooldownDeadline: Date = .distantPast
    init(context: TVAppContext) {
        self.context = context
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        bindButtons()
        bindPlaybackSnapshot()
        bindPlaybackTime()
        applySnapshot(context.playbackController.snapshot, initial: true)
    }

    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        [contentView.nowPlayingContentView.transportBar.playPauseButton]
    }

    // MARK: - Remote Presses

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = false
        for press in presses {
            switch press.type {
            case .playPause:
                handlePlayPause()
                handled = true
            case .upArrow:
                context.recordUserInteraction()
                contentView.lyricsView.scroll(byLines: -1)
                handled = true
            case .downArrow:
                context.recordUserInteraction()
                contentView.lyricsView.scroll(byLines: 1)
                handled = true
            case .leftArrow:
                context.recordUserInteraction()
                handleSeekBackward()
                handled = true
            case .rightArrow:
                context.recordUserInteraction()
                handleSeekForward()
                handled = true
            default:
                break
            }
        }
        if !handled {
            super.pressesBegan(presses, with: event)
        }
    }

    // MARK: - Bindings

    private func bindButtons() {
        let transport = contentView.nowPlayingContentView.transportBar
        transport.previousButton.addTarget(
            self,
            action: #selector(handlePrevious),
            for: .primaryActionTriggered,
        )
        transport.playPauseButton.addTarget(
            self,
            action: #selector(handlePlayPause),
            for: .primaryActionTriggered,
        )
        transport.nextButton.addTarget(
            self,
            action: #selector(handleNext),
            for: .primaryActionTriggered,
        )
    }

    private func bindPlaybackSnapshot() {
        context.playbackController.$snapshot
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in
                self?.applySnapshot(snapshot, initial: false)
            }
            .store(in: &cancellables)
    }

    private func bindPlaybackTime() {
        context.playbackController.playbackTimeSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] currentTime, duration in
                guard let self else { return }
                contentView.lyricsView.updateCurrentTime(currentTime)
                if Date() >= scrubCommitCooldownDeadline {
                    contentView.nowPlayingContentView.progressView.update(currentTime: currentTime, duration: duration)
                }
            }
            .store(in: &cancellables)
    }

    private func applySnapshot(_ snapshot: PlaybackSnapshot, initial: Bool) {
        latestSnapshot = snapshot

        let isPlaying = switch snapshot.state {
        case .playing, .buffering: true
        case .paused, .idle, .error: false
        }
        contentView.nowPlayingContentView.transportBar.setIsPlaying(isPlaying)

        let track = snapshot.currentTrack
        let subtitle: String = {
            guard let track else { return "" }
            let artist = track.artistName
            let album = track.albumName ?? ""
            if !artist.isEmpty, !album.isEmpty {
                return "\(artist) · \(album)"
            }
            return artist.isEmpty ? album : artist
        }()
        contentView.nowPlayingContentView.configure(
            title: track?.title ?? "",
            subtitle: subtitle,
            artworkURL: track?.artworkURL,
        )

        let trackID = track?.id
        if initial || trackID != lastPresentedTrackID {
            lastPresentedTrackID = trackID
            if let trackID {
                lyricsCoordinator.loadLyrics(for: Self.catalogTrackID(from: trackID))
            } else {
                lyricsCoordinator.clearDisplayedLyrics()
            }
        }
    }

    private static func catalogTrackID(from trackID: String) -> String {
        trackID.split(separator: "|").last.map(String.init) ?? trackID
    }

    // MARK: - Actions

    @objc private func handlePrevious() {
        context.playbackController.previous()
    }

    @objc private func handleSeekBackward() {
        let target = max(latestSnapshot.currentTime - 10, 0)
        scrubCommitCooldownDeadline = Date().addingTimeInterval(0.5)
        animateProgressTo(time: target)
        context.playbackController.seek(to: target)
    }

    @objc private func handleSeekForward() {
        let target = latestSnapshot.currentTime + 10
        let duration = latestSnapshot.duration
        if duration > 0, target >= duration {
            context.playbackController.next()
        } else {
            scrubCommitCooldownDeadline = Date().addingTimeInterval(0.5)
            animateProgressTo(time: target)
            context.playbackController.seek(to: target)
        }
    }

    private func animateProgressTo(time: TimeInterval) {
        let duration = latestSnapshot.duration
        contentView.nowPlayingContentView.progressView.update(currentTime: time, duration: duration, animated: true)
    }

    @objc private func handlePlayPause() {
        let snapshot = context.playbackController.snapshot
        if snapshot.state == .idle, snapshot.queue.isEmpty, context.currentSessionManifest != nil {
            Task { @MainActor [weak self] in
                await self?.context.playCurrentSession()
            }
            return
        }
        context.playbackController.togglePlayPause()
    }

    @objc private func handleNext() {
        context.playbackController.next()
    }
}
