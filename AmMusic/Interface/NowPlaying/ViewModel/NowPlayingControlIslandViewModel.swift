//
//  NowPlayingControlIslandViewModel.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import Combine
import UIKit

final class NowPlayingControlIslandViewModel {
    enum ContentSelector {
        case artwork
        case queue
        case lyrics
    }

    struct Content {
        let title: String
        let artist: String
        let currentTime: TimeInterval
        let duration: TimeInterval
        let hasActiveTrack: Bool
        let isPreviousAvailable: Bool
        let isPlaying: Bool
        let isFavorite: Bool
        let routeName: String
        let routeSymbolName: String

        var elapsedText: String {
            formattedPlaybackTime(currentTime)
        }

        var remainingText: String {
            "-\(formattedPlaybackTime(max(duration - currentTime, 0)))"
        }

        var progress: CGFloat {
            guard duration > 0 else {
                return 0
            }
            return CGFloat(min(max(currentTime / duration, 0), 1))
        }

        static let placeholder = Content(
            title: String(localized: "Nothing Playing"),
            artist: String(localized: "Pick a song to get started"),
            currentTime: 109,
            duration: 225,
            hasActiveTrack: false,
            isPreviousAvailable: true,
            isPlaying: true,
            isFavorite: false,
            routeName: String(localized: "iPhone"),
            routeSymbolName: "iphone",
        )
    }

    var content = Content.placeholder
    var currentTrackID: String = ""
    let contentSelectorPublisher = CurrentValueSubject<ContentSelector, Never>(.artwork)

    var onFavorite: () -> Void = {}
    var onPrevious: () -> Void = {}
    var onTogglePlayPause: () -> Void = {}
    var onNext: () -> Void = {}
    var onSeek: (TimeInterval) -> Void = { _ in }
    var onTitleTapped: () -> Void = {}

    var selectedContentSelector: ContentSelector {
        contentSelectorPublisher.value
    }

    func setContentSelector(_ selector: ContentSelector) {
        guard selectedContentSelector != selector else {
            return
        }
        contentSelectorPublisher.send(selector)
    }

    func favorite() {
        onFavorite()
    }

    func previous() {
        onPrevious()
    }

    func togglePlayPause() {
        onTogglePlayPause()
    }

    func next() {
        onNext()
    }

    func seek(to seconds: TimeInterval) {
        onSeek(seconds)
    }

    func titleTapped() {
        onTitleTapped()
    }
}
