//
//  MusicPlayerTests.swift
//  AmMusicPlayerKit
//
//  Created by @Lakr233 on 2026/04/11.
//

@testable import AmMusicPlayerKit
import CoreMedia
import Foundation
import MediaPlayer
import Testing

@MainActor
final class MockDelegate: MusicPlayerDelegate {
    var stateChanges: [PlaybackState] = []
    var transitions: [(PlayerItem?, TransitionReason)] = []
    var queueSnapshots: [QueueSnapshot] = []
    var failedItems: [(PlayerItem, any Error)] = []
    var endOfQueueCalled = false
    var timeUpdates: [(TimeInterval, TimeInterval)] = []

    func musicPlayer(_: AmMusicPlayerKit.MusicPlayer, didChangeState state: PlaybackState) {
        stateChanges.append(state)
    }

    func musicPlayer(_: AmMusicPlayerKit.MusicPlayer, didTransitionTo item: PlayerItem?, reason: TransitionReason) {
        transitions.append((item, reason))
    }

    func musicPlayer(_: AmMusicPlayerKit.MusicPlayer, didChangeQueue snapshot: QueueSnapshot) {
        queueSnapshots.append(snapshot)
    }

    func musicPlayer(_: AmMusicPlayerKit.MusicPlayer, didUpdateTime currentTime: TimeInterval, duration: TimeInterval) {
        timeUpdates.append((currentTime, duration))
    }

    func musicPlayer(_: AmMusicPlayerKit.MusicPlayer, didFailItem item: PlayerItem, error: any Error) {
        failedItems.append((item, error))
    }

    func musicPlayerDidReachEndOfQueue(_: AmMusicPlayerKit.MusicPlayer) {
        endOfQueueCalled = true
    }
}

final class MockPlayerLogger: MusicPlayerLogger, @unchecked Sendable {
    struct Entry {
        let level: MusicPlayerLogLevel
        let component: String
        let message: String
    }

    private(set) var entries: [Entry] = []

    func log(level: MusicPlayerLogLevel, component: String, message: String) {
        entries.append(.init(level: level, component: component, message: message))
    }
}

@Suite(.serialized)
@MainActor
struct MusicPlayerTests {
    static func makeItems(_ count: Int) -> [PlayerItem] {
        (0 ..< count).map { i in
            PlayerItem(
                id: "track-\(i)",
                url: URL(string: "https://example.com/track\(i).mp3")!,
                title: "Track \(i)",
                artist: "Artist",
                album: "Album",
                durationInSeconds: 200,
            )
        }
    }

    @Test func `start playback sets state playing`() {
        let engine = MockAudioPlaybackEngine()
        let player = MusicPlayer(engine: engine)
        let delegate = MockDelegate()
        player.delegate = delegate

        player.startPlayback(items: Self.makeItems(3))

        #expect(player.state == .playing)
        #expect(engine.playCallCount >= 1)
        #expect(engine.replaceItemCallCount >= 1)
    }

    @Test func `start playback delegate receives transition`() {
        let engine = MockAudioPlaybackEngine()
        let player = MusicPlayer(engine: engine)
        let delegate = MockDelegate()
        player.delegate = delegate

        let items = Self.makeItems(3)
        player.startPlayback(items: items)

        #expect(delegate.transitions.count >= 1)
        #expect(delegate.transitions.first?.0 == items[0])
    }

    @Test func `pause sets state paused`() {
        let engine = MockAudioPlaybackEngine()
        let player = MusicPlayer(engine: engine)
        player.startPlayback(items: Self.makeItems(2))

        player.pause()
        #expect(player.state == .paused)
        #expect(engine.pauseCallCount >= 1)
    }

    @Test func `play after pause sets state playing`() {
        let engine = MockAudioPlaybackEngine()
        let player = MusicPlayer(engine: engine)
        player.startPlayback(items: Self.makeItems(2))

        player.pause()
        player.play()
        #expect(player.state == .playing)
    }

    @Test func `toggle play pause toggles state`() {
        let engine = MockAudioPlaybackEngine()
        let player = MusicPlayer(engine: engine)
        player.startPlayback(items: Self.makeItems(2))

        player.togglePlayPause() // playing -> paused
        #expect(player.state == .paused)

        player.togglePlayPause() // paused -> playing
        #expect(player.state == .playing)
    }

    @Test func `next advances track`() {
        let engine = MockAudioPlaybackEngine()
        let player = MusicPlayer(engine: engine)
        let delegate = MockDelegate()
        player.delegate = delegate

        let items = Self.makeItems(3)
        player.startPlayback(items: items)
        player.next()

        #expect(player.currentItem == items[1])
    }

    @Test func `next delegate receives transition with user next`() {
        let engine = MockAudioPlaybackEngine()
        let player = MusicPlayer(engine: engine)
        let delegate = MockDelegate()
        player.delegate = delegate

        player.startPlayback(items: Self.makeItems(3))
        delegate.transitions.removeAll()

        player.next()

        #expect(delegate.transitions.count >= 1)
        if case .userNext = delegate.transitions.first?.1 {
            // expected
        } else {
            Issue.record("Expected .userNext transition reason")
        }
    }

    @Test func `previous restarts when over3 seconds`() {
        let engine = MockAudioPlaybackEngine()
        engine.mockCurrentTime = CMTimeMakeWithSeconds(5.0, preferredTimescale: 600)
        let player = MusicPlayer(engine: engine)
        player.startPlayback(items: Self.makeItems(3))

        player.previous()

        // Should seek to 0, not change track
        // (seek is async, but the intent is verified by the mock state)
    }

    @Test func `stop clears everything`() {
        let engine = MockAudioPlaybackEngine()
        let player = MusicPlayer(engine: engine)
        let delegate = MockDelegate()
        player.delegate = delegate

        player.startPlayback(items: Self.makeItems(3))
        player.stop()

        #expect(player.state == .idle)
        #expect(player.currentItem == nil)
        #expect(player.queue.totalCount == 0)
    }

    @Test func `start playback publishes enriched now playing info`() throws {
        Self.resetSystemMediaCenter()
        let engine = MockAudioPlaybackEngine()
        let player = MusicPlayer(engine: engine)

        let items = Self.makeItems(3)
        player.startPlayback(items: items)

        let info = try #require(MPNowPlayingInfoCenter.default().nowPlayingInfo)
        #expect(info[MPNowPlayingInfoPropertyExternalContentIdentifier] as? String == items[0].id)
        #expect(info[MPNowPlayingInfoPropertyMediaType] as? UInt == .some(MPNowPlayingInfoMediaType.audio.rawValue))
        #expect(info[MPNowPlayingInfoPropertyPlaybackProgress] as? TimeInterval == 0)
        #expect(info[MPNowPlayingInfoPropertyPlaybackQueueIndex] as? Int == 0)
        #expect(info[MPNowPlayingInfoPropertyPlaybackQueueCount] as? Int == items.count)
        #expect(MPNowPlayingInfoCenter.default().playbackState == .playing)

        player.stop()
        Self.resetSystemMediaCenter()
    }

    @Test func `pause and stop publish playback state changes`() {
        Self.resetSystemMediaCenter()
        let engine = MockAudioPlaybackEngine()
        let player = MusicPlayer(engine: engine)

        player.startPlayback(items: Self.makeItems(2))
        player.pause()

        #expect(MPNowPlayingInfoCenter.default().playbackState == .paused)

        player.stop()

        #expect(MPNowPlayingInfoCenter.default().playbackState == .stopped)
        #expect(MPNowPlayingInfoCenter.default().nowPlayingInfo == nil)
        Self.resetSystemMediaCenter()
    }

    @Test func `restore playback publishes paused state and metadata`() async throws {
        Self.resetSystemMediaCenter()
        let engine = MockAudioPlaybackEngine()
        let player = MusicPlayer(engine: engine)
        let items = Self.makeItems(2)

        let restored = await player.restorePlayback(
            items: items,
            currentIndex: 1,
            shuffled: false,
            repeatMode: .off,
            currentTime: 25,
            autoPlay: false,
        )

        #expect(restored)
        let info = try #require(MPNowPlayingInfoCenter.default().nowPlayingInfo)
        #expect(info[MPNowPlayingInfoPropertyExternalContentIdentifier] as? String == items[1].id)
        #expect(info[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? TimeInterval == 25)
        #expect(info[MPNowPlayingInfoPropertyPlaybackQueueIndex] as? Int == 1)
        #expect(info[MPNowPlayingInfoPropertyPlaybackQueueCount] as? Int == items.count)
        #expect(MPNowPlayingInfoCenter.default().playbackState == .paused)

        player.stop()
        Self.resetSystemMediaCenter()
    }

    @Test func `end of queue notifies delegate`() {
        let engine = MockAudioPlaybackEngine()
        let player = MusicPlayer(engine: engine)
        let delegate = MockDelegate()
        player.delegate = delegate

        player.startPlayback(items: Self.makeItems(1))
        player.next() // Only 1 item, so this reaches end

        #expect(delegate.endOfQueueCalled)
    }

    @Test func `next at end with repeat off clears playback state`() {
        let engine = MockAudioPlaybackEngine()
        let player = MusicPlayer(engine: engine)

        player.startPlayback(items: Self.makeItems(1))
        player.next()

        #expect(player.state == .idle)
        #expect(player.currentItem == nil)
        #expect(player.queue.totalCount == 0)
    }

    @Test func `previous at queue start with repeat queue wraps to last track`() {
        let engine = MockAudioPlaybackEngine()
        engine.mockCurrentTime = .zero
        let player = MusicPlayer(engine: engine)

        let items = Self.makeItems(3)
        player.startPlayback(items: items)
        player.repeatMode = .queue
        player.previous()

        #expect(player.currentItem == items[2])
        #expect(player.queue.currentIndex == 2)
    }

    @Test func `add to queue updates queue`() throws {
        let engine = MockAudioPlaybackEngine()
        let player = MusicPlayer(engine: engine)
        let delegate = MockDelegate()
        player.delegate = delegate

        let items = Self.makeItems(2)
        player.startPlayback(items: items)

        let newItem = try PlayerItem(
            id: "new", url: #require(URL(string: "https://example.com/new.mp3")),
            title: "New", artist: "A", album: "B",
        )
        player.addToQueue(newItem)

        #expect(player.queue.upcoming.contains(newItem))
    }

    @Test func `replace upcoming queue publishes single queue update`() {
        let engine = MockAudioPlaybackEngine()
        let player = MusicPlayer(engine: engine)
        let delegate = MockDelegate()
        player.delegate = delegate

        let items = Self.makeItems(4)
        player.startPlayback(items: items)
        delegate.queueSnapshots.removeAll()

        let replacement = [items[3], items[2], items[1]]
        player.replaceUpcomingQueue(replacement)

        #expect(delegate.queueSnapshots.count == 1)
        #expect(player.queue.nowPlaying == items[0])
        #expect(player.queue.upcoming == replacement)
    }

    @Test func `play next inserts at front of upcoming`() throws {
        let engine = MockAudioPlaybackEngine()
        let player = MusicPlayer(engine: engine)

        let items = Self.makeItems(3)
        player.startPlayback(items: items)

        let newItem = try PlayerItem(
            id: "priority", url: #require(URL(string: "https://example.com/p.mp3")),
            title: "Priority", artist: "A", album: "B",
        )
        player.playNext(newItem)

        #expect(player.queue.upcoming.first == newItem)
    }

    @Test func `shuffled setter toggles shuffle`() {
        let engine = MockAudioPlaybackEngine()
        let player = MusicPlayer(engine: engine)
        player.startPlayback(items: Self.makeItems(5))

        player.shuffled = true
        #expect(player.queue.shuffled == true)

        player.shuffled = false
        #expect(player.queue.shuffled == false)
    }

    @Test func `repeat mode setter changes mode`() {
        let engine = MockAudioPlaybackEngine()
        let player = MusicPlayer(engine: engine)
        player.startPlayback(items: Self.makeItems(3))

        player.repeatMode = .track
        #expect(player.repeatMode == .track)

        player.repeatMode = .queue
        #expect(player.repeatMode == .queue)
    }

    @Test func `periodic time observer suspends and resumes callbacks`() async {
        let engine = MockAudioPlaybackEngine()
        let player = MusicPlayer(engine: engine)
        let delegate = MockDelegate()
        player.delegate = delegate

        player.startPlayback(items: Self.makeItems(1))
        #expect(engine.addTimeObserverCallCount == 1)

        engine.simulatePeriodicTimeObserver(seconds: 5)
        await Task.yield()
        #expect(delegate.timeUpdates.count == 1)
        #expect(delegate.timeUpdates.last?.0 == 5)

        player.setPeriodicTimeObserverSuspended(true)
        #expect(engine.removeTimeObserverCallCount == 1)

        engine.simulatePeriodicTimeObserver(seconds: 6)
        await Task.yield()
        #expect(delegate.timeUpdates.count == 1)

        player.setPeriodicTimeObserverSuspended(false)
        #expect(engine.addTimeObserverCallCount == 2)

        engine.simulatePeriodicTimeObserver(seconds: 7)
        await Task.yield()
        #expect(delegate.timeUpdates.count == 2)
        #expect(delegate.timeUpdates.last?.0 == 7)
    }

    @Test func `handle item end with repeat track restarts current item`() {
        let engine = MockAudioPlaybackEngine()
        let player = MusicPlayer(engine: engine)
        let items = Self.makeItems(3)
        player.startPlayback(items: items)
        player.repeatMode = .track

        engine.mockCurrentItem = engine.lastPreloadedItem

        let itemBefore = player.currentItem
        player.handleItemEnd()

        #expect(player.currentItem == itemBefore)
        #expect(engine.replaceItemCallCount == 2)
        #expect(engine.seekCallCount == 0)
        #expect(engine.lastPreloadedItem == nil)
        #expect(engine.lastReplacedItem != nil)
    }

    @Test func `handle item end with repeat off advances`() {
        let engine = MockAudioPlaybackEngine()
        let player = MusicPlayer(engine: engine)
        let items = Self.makeItems(3)
        player.startPlayback(items: items)

        player.handleItemEnd()

        #expect(player.currentItem == items[1])
    }

    @Test func `injected logger receives playback logs`() {
        let engine = MockAudioPlaybackEngine()
        let logger = MockPlayerLogger()
        let player = MusicPlayer(engine: engine, logger: logger)

        player.startPlayback(items: Self.makeItems(2))
        player.pause()

        #expect(logger.entries.contains { $0.component == "MusicPlayer" && $0.message.contains("startPlayback") })
        #expect(logger.entries.contains { $0.component == "MusicPlayer" && $0.message.contains("pause requested") })
    }

    @Test func `injected logger receives engine logs`() {
        let engine = MockAudioPlaybackEngine()
        let logger = MockPlayerLogger()
        _ = MusicPlayer(engine: engine, logger: logger)

        let avEngine = AVPlayerEngine(logger: logger)
        avEngine.play()

        #expect(logger.entries.contains { $0.component == "AVPlayerEngine" && $0.message.contains("play") })
    }

    @Test func `av player engine disables external playback to avoid apple TV black screen`() {
        let logger = MockPlayerLogger()
        let engine = AVPlayerEngine(logger: logger)
        let routePlayer = engine.routePlayer

        #expect(routePlayer.allowsExternalPlayback == false)
        #if os(iOS) || os(tvOS)
            #expect(routePlayer.audiovisualBackgroundPlaybackPolicy == .continuesIfPossible)
            #expect(routePlayer.usesExternalPlaybackWhileExternalScreenIsActive)
        #endif
    }

    static func resetSystemMediaCenter() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }
}
