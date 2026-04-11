//
//  NowPlayingInfoManager.swift
//  AmMusicPlayerKit
//
//  Created by @Lakr233 on 2026/04/11.
//

import Foundation
import MediaPlayer

@MainActor
final class NowPlayingInfoManager {
    private static let subtitleExpirationInterval: TimeInterval = 10

    private let artworkLoader = ArtworkLoader()
    private let publisher: any NowPlayingStatePublishing
    private var artworkTask: Task<Void, Never>?
    private var currentItemID: String?
    private var currentInfo: [String: Any] = [:]
    private var originalArtist: String?
    private var subtitleExpirationTask: Task<Void, Never>?

    init(publisher: any NowPlayingStatePublishing) {
        self.publisher = publisher
    }

    func setTrack(_ item: PlayerItem) {
        subtitleExpirationTask?.cancel()
        subtitleExpirationTask = nil
        originalArtist = item.artist
        currentItemID = item.id
        currentInfo = [
            MPMediaItemPropertyTitle: item.title,
            MPMediaItemPropertyArtist: item.artist,
            MPMediaItemPropertyAlbumTitle: item.album,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: 0.0,
            MPNowPlayingInfoPropertyExternalContentIdentifier: item.id,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyPlaybackRate: 1.0,
        ]

        if let dur = item.durationInSeconds {
            currentInfo[MPMediaItemPropertyPlaybackDuration] = dur
        }

        updatePlaybackProgress()
        publishCurrentInfo()

        artworkTask?.cancel()
        if let url = item.artworkURL {
            let itemID = item.id
            artworkTask = Task { [weak self] in
                guard let self else { return }
                guard let artwork = await artworkLoader.loadArtwork(url: url, for: itemID) else {
                    return
                }
                guard currentItemID == itemID else { return }
                currentInfo[MPMediaItemPropertyArtwork] = artwork
                publishCurrentInfo()
            }
        }
    }

    func updateElapsedTime(_ time: TimeInterval) {
        guard currentItemID != nil else { return }
        currentInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = time
        updatePlaybackProgress()
        publishCurrentInfo()
    }

    func updateRate(_ rate: Float) {
        guard currentItemID != nil else { return }
        currentInfo[MPNowPlayingInfoPropertyPlaybackRate] = rate
        publishCurrentInfo()
    }

    func updateQueueInfo(index: Int, count: Int) {
        guard currentItemID != nil else { return }
        currentInfo[MPNowPlayingInfoPropertyPlaybackQueueIndex] = index
        currentInfo[MPNowPlayingInfoPropertyPlaybackQueueCount] = count
        publishCurrentInfo()
    }

    func updatePlaybackState(_ state: PlaybackState) {
        publisher.playbackState = mediaPlaybackState(for: state)
    }

    func updateSubtitle(_ text: String?) {
        guard currentItemID != nil else { return }

        subtitleExpirationTask?.cancel()
        subtitleExpirationTask = nil

        guard let text, !text.isEmpty else {
            if let originalArtist {
                currentInfo[MPMediaItemPropertyArtist] = originalArtist
                publishCurrentInfo()
            }
            return
        }

        currentInfo[MPMediaItemPropertyArtist] = text
        publishCurrentInfo()

        subtitleExpirationTask = Task { [weak self] in
            let nanoseconds = UInt64(Self.subtitleExpirationInterval * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            guard let self, let originalArtist else { return }
            currentInfo[MPMediaItemPropertyArtist] = originalArtist
            publishCurrentInfo()
        }
    }

    func clear() {
        subtitleExpirationTask?.cancel()
        subtitleExpirationTask = nil
        originalArtist = nil
        artworkTask?.cancel()
        artworkTask = nil
        artworkLoader.cancelCurrent()
        currentItemID = nil
        currentInfo = [:]
        publisher.playbackState = .stopped
        publisher.nowPlayingInfo = nil
    }

    private func publishCurrentInfo() {
        publisher.nowPlayingInfo = currentInfo
    }

    private func updatePlaybackProgress() {
        guard let elapsed = currentInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? TimeInterval,
              let duration = currentInfo[MPMediaItemPropertyPlaybackDuration] as? TimeInterval,
              duration.isFinite,
              duration > 0
        else {
            currentInfo.removeValue(forKey: MPNowPlayingInfoPropertyPlaybackProgress)
            return
        }

        let progress = min(max(elapsed / duration, 0), 1)
        guard progress.isFinite else {
            currentInfo.removeValue(forKey: MPNowPlayingInfoPropertyPlaybackProgress)
            return
        }

        currentInfo[MPNowPlayingInfoPropertyPlaybackProgress] = progress
    }

    private func mediaPlaybackState(for state: PlaybackState) -> MPNowPlayingPlaybackState {
        switch state {
        case .idle, .error:
            .stopped
        case .playing, .buffering:
            .playing
        case .paused:
            .paused
        }
    }
}
