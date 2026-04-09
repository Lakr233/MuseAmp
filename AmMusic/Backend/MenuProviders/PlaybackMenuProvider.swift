import UIKit

final class PlaybackMenuProvider {
    private let playbackController: PlaybackController

    init(playbackController: PlaybackController) {
        self.playbackController = playbackController
    }

    func songPrimaryActions(
        trackProvider: @escaping () -> PlaybackTrack?,
        queueProvider: @escaping () -> [PlaybackTrack],
        sourceProvider: @escaping () -> PlaybackSource
    ) -> [UIMenuElement] {
        [
            UIDeferredMenuElement.uncached { [weak self] completion in
                guard let self, let track = trackProvider() else {
                    completion([])
                    return
                }

                let isLiked = playbackController.isLiked(trackID: track.id)
                let playTitle = String(localized: "Play")
                let likeTitle = isLiked ? String(localized: "Unlike") : String(localized: "Like")
                let likeImage = UIImage(systemName: isLiked ? "heart.slash" : "heart")
                let playNextAction = UIAction(
                    title: String(localized: "Play Next"),
                    image: UIImage(systemName: "text.insert")
                ) { [weak self] _ in
                    guard let self else { return }
                    Task { @MainActor in
                        let count = await self.playbackController.playNext([track])
                        PlaybackFeedbackPresenter.presentPlayNextSuccess(count: count, tracks: [track])
                    }
                }
                let addToQueueAction = UIAction(
                    title: String(localized: "Add to Queue"),
                    image: UIImage(systemName: "text.append")
                ) { [weak self] _ in
                    guard let self else { return }
                    Task { @MainActor in
                        let count = await self.playbackController.addToQueue([track])
                        PlaybackFeedbackPresenter.presentAddToQueueSuccess(count: count, tracks: [track])
                    }
                }

                completion([
                    UIAction(
                        title: playTitle,
                        image: UIImage(systemName: "play.fill")
                    ) { [weak self] _ in
                        guard let self else { return }
                        Task { @MainActor in
                            let didPlay = await self.playbackController.play(
                                track: track,
                                in: queueProvider(),
                                source: sourceProvider()
                            )
                            if didPlay {
                                PlaybackFeedbackPresenter.presentPlaySuccess(tracks: [track], startIndex: 0)
                            } else {
                                PlaybackFeedbackPresenter.presentFailure(title: playTitle)
                            }
                        }
                    },
                    Self.makePlayAtMenu(children: [playNextAction, addToQueueAction]),
                    UIAction(
                        title: likeTitle,
                        image: likeImage
                    ) { [weak self] _ in
                        _ = self?.playbackController.toggleLiked(track)
                    },
                ])
            },
        ]
    }

    func listPrimaryActions(
        tracksProvider: @escaping () -> [PlaybackTrack],
        sourceProvider: @escaping () -> PlaybackSource
    ) -> [UIMenuElement] {
        [
            UIDeferredMenuElement.uncached { [weak self] completion in
                guard let self else {
                    completion([])
                    return
                }
                let tracks = tracksProvider()
                guard !tracks.isEmpty else {
                    completion([])
                    return
                }
                let shufflePlayAction = UIAction(
                    title: String(localized: "Shuffle Play"),
                    image: UIImage(systemName: "shuffle")
                ) { [weak self] _ in
                    guard let self else { return }
                    Task { @MainActor in
                        let didPlay = await self.playbackController.play(
                            tracks: tracks,
                            source: sourceProvider(),
                            shuffle: true
                        )
                        if didPlay {
                            PlaybackFeedbackPresenter.presentPlaySuccess(tracks: tracks, shuffle: true)
                        } else {
                            PlaybackFeedbackPresenter.presentFailure(title: String(localized: "Shuffle Play"))
                        }
                    }
                }
                let playNextAction = UIAction(
                    title: String(localized: "Play Next"),
                    image: UIImage(systemName: "text.insert")
                ) { [weak self] _ in
                    guard let self else { return }
                    Task { @MainActor in
                        let count = await self.playbackController.playNext(tracks)
                        PlaybackFeedbackPresenter.presentPlayNextSuccess(count: count, tracks: tracks)
                    }
                }
                let addToQueueAction = UIAction(
                    title: String(localized: "Add to Queue"),
                    image: UIImage(systemName: "text.append")
                ) { [weak self] _ in
                    guard let self else { return }
                    Task { @MainActor in
                        let count = await self.playbackController.addToQueue(tracks)
                        PlaybackFeedbackPresenter.presentAddToQueueSuccess(count: count, tracks: tracks)
                    }
                }

                completion([
                    UIAction(
                        title: String(localized: "Play"),
                        image: UIImage(systemName: "play.fill")
                    ) { [weak self] _ in
                        guard let self else { return }
                        Task { @MainActor in
                            let didPlay = await self.playbackController.play(
                                tracks: tracks,
                                source: sourceProvider()
                            )
                            if didPlay {
                                PlaybackFeedbackPresenter.presentPlaySuccess(tracks: tracks, startIndex: 0)
                            } else {
                                PlaybackFeedbackPresenter.presentFailure(title: String(localized: "Play"))
                            }
                        }
                    },
                    Self.makePlayAtMenu(children: [shufflePlayAction, playNextAction, addToQueueAction]),
                ])
            },
        ]
    }
}

extension PlaybackMenuProvider {
    static func makePlayAtMenu(children: [UIMenuElement]) -> UIMenu {
        UIMenu(
            title: String(localized: "Play At..."),
            image: UIImage(systemName: "ellipsis.circle"),
            children: children
        )
    }
}
