//
//  NowPlayingCompactController+Playback.swift
//  MuseAmp
//
//  Created by @Lakr233 on 2026/04/11.
//

import MuseAmpPlayerKit
import UIKit

extension NowPlayingCompactController {
    func handleContentSelectorChange(_ selector: NowPlayingControlIslandViewModel.ContentSelector) {
        updatePopupCloseButtonAppearance(for: selector)
        pageViewController.setSelector(selector, animated: true)
        refreshLyricsScreenAwakeHold()
    }

    func updateQueuePresentation(queue: [PlaybackTrack], playerIndex: Int?, repeatMode: RepeatMode) {
        pageViewController.updateQueue(
            queue: queue,
            playerIndex: playerIndex,
            repeatMode: repeatMode,
        )
    }

    func applySupplementalPlaybackProgress(for snapshot: PlaybackSnapshot) {
        updateTransportLyricLine(for: snapshot)
    }

    func updateTransportSongMenu(for snapshot: PlaybackSnapshot) {
        guard let track = snapshot.currentTrack else {
            pageViewController.updateTransportSongMenu(nil)
            return
        }
        let favoriteSection = UIDeferredMenuElement.uncached { [weak self] completion in
            guard let self else {
                completion([])
                return
            }
            let isLiked = currentPlaybackSnapshot.isCurrentTrackLiked
            let action = UIAction(
                title: isLiked
                    ? String(localized: "Unlike")
                    : String(localized: "Like"),
                image: UIImage(systemName: isLiked ? "heart.fill" : "heart"),
            ) { [weak self] _ in
                _ = self?.environment.playbackController.toggleLikedCurrentTrack()
            }
            completion([UIMenu(options: .displayInline, children: [action])])
        }

        let baseMenu = songContextMenuProvider.menu(
            title: track.title,
            for: track.playlistEntry,
            context: .library,
            configuration: .init(
                libraryActions: [makeShowPlaybackQueueAction()],
                lyricsActionsBeforeReload: [makeShowLyricsAction()],
            ),
        )
        let children: [UIMenuElement] = [favoriteSection] + (baseMenu?.children ?? [])
        let menu = UIMenu(
            title: baseMenu?.title ?? "",
            children: children,
        )
        pageViewController.updateTransportSongMenu(menu)
    }

    func updateTransportLyricLine(for _: PlaybackSnapshot) {
        pageViewController.updateCurrentLyricLine(nil)
    }

    func refreshPlayingContent(animated: Bool) {
        let snapshot = currentPlaybackSnapshot
        let selector = controlIslandViewModel.selectedContentSelector
        let currentTrackID = snapshot.currentTrack?.id ?? "nil"
        let artworkDescription = nowPlayingLogURLDescription(snapshot.currentTrack?.artworkURL)
        AppLog.info(
            self,
            "refreshPlayingContent selector=\(String(describing: selector)) trackID=\(currentTrackID) artwork=\(artworkDescription) animated=\(animated)",
        )

        pageViewController.setSelector(selector, animated: animated)
        updateTransportSongMenu(for: snapshot)
        updateTransportLyricLine(for: snapshot)
    }
}
