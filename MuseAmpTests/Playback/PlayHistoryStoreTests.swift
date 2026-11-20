import Foundation
@testable import MuseAmp
import MuseAmpDatabaseKit
import Testing

@Suite(.serialized)
@MainActor
struct PlayHistoryStoreTests {
    private func makeStore(_ sandbox: TestLibrarySandbox) -> PlayHistoryStore {
        PlayHistoryStore(fileURL: LibraryPaths(baseDirectory: sandbox.baseDirectory).playHistoryURL)
    }

    // MARK: - Threshold

    @Test
    func `a play counts after more than thirty seconds`() {
        #expect(!PlayHistoryStore.countsAsPlayed(listenedSeconds: 30, duration: 600))
        #expect(PlayHistoryStore.countsAsPlayed(listenedSeconds: 30.5, duration: 600))
    }

    @Test
    func `a play counts at half of a short song`() {
        #expect(!PlayHistoryStore.countsAsPlayed(listenedSeconds: 9.9, duration: 20))
        #expect(PlayHistoryStore.countsAsPlayed(listenedSeconds: 10, duration: 20))
    }

    @Test
    func `an unknown duration needs the thirty seconds`() {
        #expect(!PlayHistoryStore.countsAsPlayed(listenedSeconds: 20, duration: 0))
        #expect(!PlayHistoryStore.countsAsPlayed(listenedSeconds: 20, duration: .nan))
        #expect(PlayHistoryStore.countsAsPlayed(listenedSeconds: 31, duration: 0))
    }

    @Test
    func `tracker records a play once it passes the threshold, only once`() {
        var tracker = PlayHistoryTracker()
        #expect(tracker.begin(trackID: "a", albumID: "x", duration: 200, isPlaying: true, now: 100) == nil)
        #expect(tracker.takeQualifiedPlay(now: 120) == nil)
        let play = tracker.takeQualifiedPlay(now: 130.5)
        #expect(play?.trackID == "a")
        #expect(play?.albumID == "x")
        #expect(tracker.takeQualifiedPlay(now: 190) == nil)
        #expect(tracker.begin(trackID: "b", albumID: nil, duration: 200, isPlaying: true, now: 191) == nil)
    }

    @Test
    func `tracker does not record a skip`() {
        var tracker = PlayHistoryTracker()
        _ = tracker.begin(trackID: "a", albumID: nil, duration: 240, isPlaying: true, now: 0)
        let finished = tracker.begin(trackID: "b", albumID: nil, duration: 240, isPlaying: true, now: 5)
        #expect(finished == nil)
    }

    @Test
    func `tracker records a finished short song on the transition`() {
        var tracker = PlayHistoryTracker()
        _ = tracker.begin(trackID: "a", albumID: nil, duration: 8, isPlaying: true, now: 0)
        let finished = tracker.begin(trackID: "b", albumID: nil, duration: 8, isPlaying: true, now: 8)
        #expect(finished?.trackID == "a")
    }

    @Test
    func `tracker does not count paused time`() {
        var tracker = PlayHistoryTracker()
        _ = tracker.begin(trackID: "a", albumID: nil, duration: 300, isPlaying: true, now: 0)
        tracker.setPlaying(false, now: 20)
        #expect(tracker.takeQualifiedPlay(now: 500) == nil)
        tracker.setPlaying(true, now: 500)
        #expect(tracker.takeQualifiedPlay(now: 505) == nil)
        #expect(tracker.takeQualifiedPlay(now: 511)?.trackID == "a")
    }

    @Test
    func `tracker uses the player duration once it is known`() {
        var tracker = PlayHistoryTracker()
        _ = tracker.begin(trackID: "a", albumID: nil, duration: 0, isPlaying: true, now: 0)
        #expect(tracker.takeQualifiedPlay(now: 6) == nil)
        tracker.updateDuration(12)
        #expect(tracker.takeQualifiedPlay(now: 6)?.trackID == "a")
    }

    @Test
    func `starting the same song again is a new play`() {
        var tracker = PlayHistoryTracker()
        _ = tracker.begin(trackID: "a", albumID: nil, duration: 10, isPlaying: true, now: 0)
        #expect(tracker.takeQualifiedPlay(now: 6)?.trackID == "a")
        _ = tracker.begin(trackID: "a", albumID: nil, duration: 10, isPlaying: true, now: 10)
        #expect(tracker.takeQualifiedPlay(now: 16)?.trackID == "a")
    }

    // MARK: - Store

    @Test
    func `recordPlay persists and reloads`() {
        let sandbox = TestLibrarySandbox()
        let store = makeStore(sandbox)
        let date = Date(timeIntervalSinceReferenceDate: 1000)
        store.recordPlay(trackID: "t1", albumID: "al1", at: date)
        store.recordPlay(trackID: "t1", albumID: "al1", at: date.addingTimeInterval(60))

        let reloaded = makeStore(sandbox)
        #expect(reloaded.lastPlayedDate(forTrackID: "t1") == date.addingTimeInterval(60))
        #expect(reloaded.entries["t1"]?.playCount == 2)
        #expect(reloaded.entries["t1"]?.albumID == "al1")
    }

    @Test
    func `recordPlay posts a change notification`() {
        let sandbox = TestLibrarySandbox()
        let store = makeStore(sandbox)
        let counter = NotificationCounter()
        NotificationCenter.default.addObserver(
            counter,
            selector: #selector(NotificationCounter.receive),
            name: .playHistoryDidChange,
            object: store,
        )
        store.recordPlay(trackID: "t1", albumID: nil)
        store.clear()
        NotificationCenter.default.removeObserver(counter)
        #expect(counter.count == 2)
    }

    @Test
    func `album recency is the latest play of any of its songs`() {
        let sandbox = TestLibrarySandbox()
        let store = makeStore(sandbox)
        let base = Date(timeIntervalSinceReferenceDate: 5000)
        store.recordPlay(trackID: "a1", albumID: "A", at: base)
        store.recordPlay(trackID: "a2", albumID: "A", at: base.addingTimeInterval(300))
        store.recordPlay(trackID: "b1", albumID: "B", at: base.addingTimeInterval(100))
        store.recordPlay(trackID: "a1", albumID: "A", at: base.addingTimeInterval(50))

        let dates = store.albumLastPlayedDates()
        #expect(dates["A"] == base.addingTimeInterval(300))
        #expect(dates["B"] == base.addingTimeInterval(100))
        #expect(dates.count == 2)
    }

    @Test
    func `clear removes history and the file`() {
        let sandbox = TestLibrarySandbox()
        let store = makeStore(sandbox)
        store.recordPlay(trackID: "t1", albumID: "al1")
        #expect(FileManager.default.fileExists(atPath: store.fileURL.path))

        store.clear()
        #expect(store.isEmpty)
        #expect(store.lastPlayedDate(forTrackID: "t1") == nil)
        #expect(store.albumLastPlayedDates().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: store.fileURL.path))
        #expect(makeStore(sandbox).isEmpty)
    }

    // MARK: - Ordering

    @Test
    func `recently played puts the newest play first`() {
        let base = Date(timeIntervalSinceReferenceDate: 0)
        let played: [String: Date] = [
            "c": base.addingTimeInterval(10),
            "a": base.addingTimeInterval(30),
            "d": base.addingTimeInterval(20),
        ]
        let sorted = PlayHistoryStore.sortedByRecentlyPlayed(["a", "b", "c", "d", "e"]) { played[$0] }
        #expect(sorted == ["a", "d", "c", "b", "e"])
    }

    @Test
    func `never played items keep the incoming order`() {
        let played = ["m": Date(timeIntervalSinceReferenceDate: 1)]
        let input = ["z", "y", "m", "x", "w"]
        let sorted = PlayHistoryStore.sortedByRecentlyPlayed(input) { played[$0] }
        #expect(sorted == ["m", "z", "y", "x", "w"])
    }

    @Test
    func `with no history the order is unchanged`() {
        let input = ["q", "b", "k", "a"]
        let sorted = PlayHistoryStore.sortedByRecentlyPlayed(input) { _ in nil }
        #expect(sorted == input)
    }

    @Test
    func `after clearing the sort falls back to the original order`() {
        let sandbox = TestLibrarySandbox()
        let store = makeStore(sandbox)
        store.recordPlay(trackID: "c", albumID: nil)
        let input = ["a", "b", "c"]
        #expect(PlayHistoryStore.sortedByRecentlyPlayed(input) { store.lastPlayedDate(forTrackID: $0) } == ["c", "a", "b"])

        store.clear()
        #expect(PlayHistoryStore.sortedByRecentlyPlayed(input) { store.lastPlayedDate(forTrackID: $0) } == input)
    }

    @Test
    func `equal play times keep the incoming order`() {
        let date = Date(timeIntervalSinceReferenceDate: 42)
        let sorted = PlayHistoryStore.sortedByRecentlyPlayed(["b", "a", "c"]) { $0 == "c" ? nil : date }
        #expect(sorted == ["b", "a", "c"])
    }
}

private final class NotificationCounter: NSObject {
    private(set) var count = 0

    @objc func receive() {
        count += 1
    }
}
