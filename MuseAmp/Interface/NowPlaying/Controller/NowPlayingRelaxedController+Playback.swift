//
//  NowPlayingRelaxedController+Playback.swift
//  MuseAmp
//
//  Created by @Lakr233 on 2026/04/11.
//

import MuseAmpPlayerKit
import UIKit

extension NowPlayingRelaxedController {
    func handleContentSelectorChange(_ selector: NowPlayingControlIslandViewModel.ContentSelector) {
        switch selector {
        case .lyrics, .artwork:
            switchRightPanel(to: .lyrics, animated: true)
        case .queue:
            switchRightPanel(to: .queue, animated: true)
        }
    }

    func updateQueuePresentation(queue: [PlaybackTrack], playerIndex: Int?, repeatMode: RepeatMode) {
        listSectionView.updateQueue(
            queue: queue,
            playerIndex: playerIndex,
            repeatMode: repeatMode,
        )
    }

    func applySupplementalPlaybackProgress(for _: PlaybackSnapshot) {}

    func animateTrackTransitionIfNeeded(shouldAnimate: Bool) {
        guard shouldAnimate else { return }
        view.setNeedsLayout()
        Interface.springAnimate(
            duration: 0.42,
            dampingRatio: 0.9,
            initialVelocity: 0.8,
        ) {
            self.view.layoutIfNeeded()
        }
    }

    func refreshPlayingContent(animated: Bool) {
        let snapshot = currentPlaybackSnapshot
        let currentTrackID = snapshot.currentTrack?.id ?? "nil"
        let artworkDescription = nowPlayingLogURLDescription(snapshot.currentTrack?.artworkURL)

        AppLog.info(
            self,
            "refreshPlayingContent panel=\(String(describing: currentRightPanel)) trackID=\(currentTrackID) artwork=\(artworkDescription) animated=\(animated)",
        )

        updateTransportSongMenu(for: snapshot)
    }

    func updateTransportSongMenu(for snapshot: PlaybackSnapshot) {
        guard let track = snapshot.currentTrack else {
            relaxedTransportView.setSongMenu(nil)
            return
        }
        let menu = songContextMenuProvider.menu(
            title: track.title,
            for: track.playlistEntry,
            context: .library,
            configuration: .init(
                libraryActions: [makeShowPlaybackQueueAction()],
                lyricsActionsBeforeReload: [makeShowLyricsAction()],
            ),
        )
        relaxedTransportView.setSongMenu(menu)
    }
}
