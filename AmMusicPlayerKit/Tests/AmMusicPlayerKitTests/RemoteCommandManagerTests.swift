//
//  RemoteCommandManagerTests.swift
//  AmMusicPlayerKit
//
//  Created by @Lakr233 on 2026/04/11.
//

@testable import AmMusicPlayerKit
import MediaPlayer
import Testing

@Suite(.serialized)
@MainActor
struct RemoteCommandManagerTests {
    final class CommandProvider: RemoteCommandCenterProviding {
        let commandCenter = MPRemoteCommandCenter.shared()
    }

    @Test func `register enables core commands`() {
        let provider = CommandProvider()
        let manager = RemoteCommandManager(provider: provider)
        let player = MusicPlayer(engine: MockAudioPlaybackEngine())
        resetCommandCenter()

        manager.register(player: player)

        #expect(provider.commandCenter.playCommand.isEnabled)
        #expect(provider.commandCenter.pauseCommand.isEnabled)
        #expect(provider.commandCenter.togglePlayPauseCommand.isEnabled)
        #expect(provider.commandCenter.nextTrackCommand.isEnabled)
        #expect(provider.commandCenter.previousTrackCommand.isEnabled)
        #expect(provider.commandCenter.stopCommand.isEnabled)
        #expect(provider.commandCenter.changePlaybackPositionCommand.isEnabled)
        #expect(provider.commandCenter.changeRepeatModeCommand.isEnabled)
        #expect(provider.commandCenter.changeShuffleModeCommand.isEnabled)

        manager.unregister()
        resetCommandCenter()
    }

    @Test func `update enabled commands toggles next and previous from queue state`() throws {
        let provider = CommandProvider()
        let manager = RemoteCommandManager(provider: provider)
        let player = MusicPlayer(engine: MockAudioPlaybackEngine())
        resetCommandCenter()
        manager.register(player: player)

        let current = try PlayerItem(
            id: "track-1",
            url: #require(URL(string: "https://example.com/track-1.mp3")),
            title: "Track 1",
            artist: "Artist 1",
            album: "Album 1",
        )

        manager.updateEnabledCommands(
            queue: QueueSnapshot(
                history: [],
                nowPlaying: current,
                upcoming: [],
                shuffled: false,
                repeatMode: .off,
            ),
        )

        #expect(provider.commandCenter.previousTrackCommand.isEnabled)
        #expect(provider.commandCenter.nextTrackCommand.isEnabled == false)

        manager.updateEnabledCommands(
            queue: QueueSnapshot(
                history: [],
                nowPlaying: current,
                upcoming: [current],
                shuffled: false,
                repeatMode: .off,
            ),
        )

        #expect(provider.commandCenter.nextTrackCommand.isEnabled)

        manager.unregister()
        resetCommandCenter()
    }

    @Test func `unregister disables commands`() {
        let provider = CommandProvider()
        let manager = RemoteCommandManager(provider: provider)
        let player = MusicPlayer(engine: MockAudioPlaybackEngine())
        resetCommandCenter()
        manager.register(player: player)

        manager.unregister()

        #expect(provider.commandCenter.playCommand.isEnabled == false)
        #expect(provider.commandCenter.pauseCommand.isEnabled == false)
        #expect(provider.commandCenter.togglePlayPauseCommand.isEnabled == false)
        #expect(provider.commandCenter.nextTrackCommand.isEnabled == false)
        #expect(provider.commandCenter.previousTrackCommand.isEnabled == false)
        #expect(provider.commandCenter.stopCommand.isEnabled == false)
        #expect(provider.commandCenter.changePlaybackPositionCommand.isEnabled == false)
        #expect(provider.commandCenter.changeRepeatModeCommand.isEnabled == false)
        #expect(provider.commandCenter.changeShuffleModeCommand.isEnabled == false)
        #expect(provider.commandCenter.likeCommand.isEnabled == false)

        resetCommandCenter()
    }

    private func resetCommandCenter() {
        RemoteCommandManager(provider: CommandProvider()).unregister()
    }
}
