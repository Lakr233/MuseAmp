//
//  PopupBarPagingHandler.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import Kingfisher
import LNPopupController
import UIKit

@MainActor
final class PopupBarPagingHandler: NSObject {
    private let playbackController: PlaybackController
    private let onRequestUpdate: () -> Void

    var cooldownDate: Date = .distantPast

    var isCooldownActive: Bool {
        Date() < cooldownDate
    }

    init(playbackController: PlaybackController, onRequestUpdate: @escaping () -> Void) {
        self.playbackController = playbackController
        self.onRequestUpdate = onRequestUpdate
    }

    // MARK: - Data Source

    func popupItemBefore(_ popupItem: LNPopupItem) -> LNPopupItem? {
        let snapshot = playbackController.snapshot
        guard let queueIndex = popupItem.userInfo?["queueIndex"] as? Int else { return nil }
        let previousIndex = queueIndex - 1
        guard snapshot.queue.indices.contains(previousIndex) else { return nil }
        return makePopupItem(for: snapshot.queue[previousIndex], queueIndex: previousIndex)
    }

    func popupItemAfter(_ popupItem: LNPopupItem) -> LNPopupItem? {
        let snapshot = playbackController.snapshot
        guard let queueIndex = popupItem.userInfo?["queueIndex"] as? Int else { return nil }
        let nextIndex = queueIndex + 1
        guard snapshot.queue.indices.contains(nextIndex) else { return nil }
        return makePopupItem(for: snapshot.queue[nextIndex], queueIndex: nextIndex)
    }

    // MARK: - Delegate

    func didDisplay(_ newPopupItem: LNPopupItem, previous previousPopupItem: LNPopupItem?) {
        guard let previousPopupItem,
              let newIndex = newPopupItem.userInfo?["queueIndex"] as? Int,
              let previousIndex = previousPopupItem.userInfo?["queueIndex"] as? Int,
              newIndex != previousIndex
        else { return }

        cooldownDate = Date().addingTimeInterval(0.5)
        playbackController.skipToQueueTrack(at: newIndex)

        NSObject.cancelPreviousPerformRequests(
            withTarget: self,
            selector: #selector(deferredSyncAfterPaging),
            object: nil,
        )
        perform(#selector(deferredSyncAfterPaging), with: nil, afterDelay: 0.5)
    }

    @objc private func deferredSyncAfterPaging() {
        cooldownDate = .distantPast
        onRequestUpdate()
    }

    // MARK: - Item Construction

    private static let placeholderArtwork: UIImage = Bundle.appIcon

    private func makePopupItem(for track: PlaybackTrack, queueIndex: Int) -> LNPopupItem {
        let item = LNPopupItem()
        item.title = track.title.sanitizedTrackTitle
        item.subtitle = track.artistName
        item.image = Self.placeholderArtwork
        item.progress = 0
        item.userInfo = [
            "trackID": track.id,
            "queueIndex": queueIndex,
        ]

        if let artworkURL = track.artworkURL {
            if artworkURL.isFileURL {
                item.image = UIImage(contentsOfFile: artworkURL.path) ?? Self.placeholderArtwork
            } else {
                KingfisherManager.shared.retrieveImage(with: artworkURL) { result in
                    if case let .success(value) = result {
                        DispatchQueue.main.async {
                            item.image = value.image
                        }
                    }
                }
            }
        }

        return item
    }
}
