//
//  RemoteCommandManager.swift
//  AmMusicPlayerKit
//
//  Created by @Lakr233 on 2026/04/11.
//

import MediaPlayer

@MainActor
final class RemoteCommandManager {
    private weak var player: MusicPlayer?
    private let provider: any RemoteCommandCenterProviding

    init(provider: any RemoteCommandCenterProviding) {
        self.provider = provider
    }

    private var commandCenter: MPRemoteCommandCenter {
        provider.commandCenter
    }

    func register(player: MusicPlayer) {
        self.player = player

        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak player] _ in
            player?.play()
            return .success
        }

        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak player] _ in
            player?.pause()
            return .success
        }

        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { [weak player] _ in
            player?.togglePlayPause()
            return .success
        }

        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { [weak player] _ in
            player?.next()
            return .success
        }

        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { [weak player] _ in
            player?.previous()
            return .success
        }

        commandCenter.stopCommand.isEnabled = true
        commandCenter.stopCommand.addTarget { [weak player] _ in
            player?.stop()
            return .success
        }

        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.addTarget { [weak player] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            Task { @MainActor in
                await player?.seek(to: event.positionTime)
            }
            return .success
        }

        commandCenter.changeRepeatModeCommand.isEnabled = true
        commandCenter.changeRepeatModeCommand.addTarget { [weak player] event in
            guard let event = event as? MPChangeRepeatModeCommandEvent else {
                return .commandFailed
            }
            switch event.repeatType {
            case .off: player?.repeatMode = .off
            case .one: player?.repeatMode = .track
            case .all: player?.repeatMode = .queue
            @unknown default: break
            }
            return .success
        }

        commandCenter.changeShuffleModeCommand.isEnabled = true
        commandCenter.changeShuffleModeCommand.addTarget { [weak player] event in
            guard let event = event as? MPChangeShuffleModeCommandEvent else {
                return .commandFailed
            }
            player?.shuffled = (event.shuffleType != .off)
            return .success
        }

        commandCenter.likeCommand.addTarget { [weak player] _ in
            guard let player else {
                return .commandFailed
            }
            return player.handleLikeCommand()
        }

        updateLikeCommand(
            isEnabled: player.canHandleLikeCommand,
            isActive: player.currentItemLiked,
            localizedTitle: player.likeCommandLocalizedTitle,
            localizedShortTitle: player.likeCommandLocalizedShortTitle,
        )
    }

    func updateEnabledCommands(queue: QueueSnapshot) {
        // Previous is always enabled when playing (restart current track behavior)
        commandCenter.previousTrackCommand.isEnabled = queue.nowPlaying != nil
        commandCenter.nextTrackCommand.isEnabled = !queue.upcoming.isEmpty || queue.repeatMode != .off
    }

    func updateLikeCommand(
        isEnabled: Bool,
        isActive: Bool,
        localizedTitle: String,
        localizedShortTitle: String?,
    ) {
        commandCenter.likeCommand.isEnabled = isEnabled
        commandCenter.likeCommand.isActive = isActive
        commandCenter.likeCommand.localizedTitle = localizedTitle
        if let localizedShortTitle {
            commandCenter.likeCommand.localizedShortTitle = localizedShortTitle
        }
    }

    func unregister() {
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.playCommand.isEnabled = false
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.pauseCommand.isEnabled = false
        commandCenter.togglePlayPauseCommand.removeTarget(nil)
        commandCenter.togglePlayPauseCommand.isEnabled = false
        commandCenter.nextTrackCommand.removeTarget(nil)
        commandCenter.nextTrackCommand.isEnabled = false
        commandCenter.previousTrackCommand.removeTarget(nil)
        commandCenter.previousTrackCommand.isEnabled = false
        commandCenter.stopCommand.removeTarget(nil)
        commandCenter.stopCommand.isEnabled = false
        commandCenter.changePlaybackPositionCommand.removeTarget(nil)
        commandCenter.changePlaybackPositionCommand.isEnabled = false
        commandCenter.changeRepeatModeCommand.removeTarget(nil)
        commandCenter.changeRepeatModeCommand.isEnabled = false
        commandCenter.changeShuffleModeCommand.removeTarget(nil)
        commandCenter.changeShuffleModeCommand.isEnabled = false
        commandCenter.likeCommand.removeTarget(nil)
        commandCenter.likeCommand.isEnabled = false
        commandCenter.likeCommand.isActive = false
    }
}
