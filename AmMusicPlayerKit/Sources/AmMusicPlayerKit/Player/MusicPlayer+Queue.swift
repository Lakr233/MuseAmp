//
//  MusicPlayer+Queue.swift
//  AmMusicPlayerKit
//
//  Created by @Lakr233 on 2026/04/11.
//

public extension MusicPlayer {
    func next() {
        log(.info, "next requested current=\(describe(item: currentItem))")
        let next = playbackQueue.advance()
        if let next {
            if engine.advanceToPreloadedItem() {
                log(.verbose, "using preloaded item for next item=\(describe(item: next))")
                continueWithCurrentEngineItem(next, reason: .userNext)
            } else {
                loadAndPlay(next, reason: .userNext)
            }
        } else if repeatMode == .off {
            log(.info, "next reached end of queue with repeat off")
            delegate?.musicPlayerDidReachEndOfQueue(self)
            stop()
        } else {
            log(.verbose, "next found no next item repeatMode=\(repeatMode)")
        }
    }

    func previous() {
        log(.info, "previous requested currentTime=\(currentTime) current=\(describe(item: currentItem))")
        let result = playbackQueue.rewind(currentTime: currentTime)
        switch result {
        case .restart:
            log(.verbose, "previous restarting current item")
            Task { await seek(to: 0) }
        case let .previous(item):
            log(.verbose, "previous moving to item=\(describe(item: item))")
            loadAndPlay(item, reason: .userPrevious)
        }
    }

    func skip(to index: Int) {
        log(.info, "skip requested index=\(index)")
        guard let item = playbackQueue.skip(to: index) else {
            log(.warning, "skip ignored because index=\(index) is unavailable")
            return
        }
        loadAndPlay(item, reason: .userSkip(toIndex: index))
    }

    func skipToQueueIndex(_ index: Int) {
        log(.info, "skipToQueueIndex requested index=\(index)")
        guard let item = playbackQueue.jump(to: index) else {
            log(.warning, "skipToQueueIndex ignored because index=\(index) is unavailable")
            return
        }
        loadAndPlay(item, reason: .userSkip(toIndex: index))
    }

    func playNext(_ item: PlayerItem) {
        log(.info, "playNext item=\(describe(item: item))")
        playbackQueue.playNext(item)
        preloadNextItem()
        delegate?.musicPlayer(self, didChangeQueue: queue)
        log(.verbose, "queue after playNext \(describe(queue: queue))")
    }

    func playNext(_ items: [PlayerItem]) {
        guard !items.isEmpty else {
            log(.warning, "playNext ignored because items are empty")
            return
        }

        log(.info, "playNext count=\(items.count)")
        playbackQueue.playNext(items)
        preloadNextItem()
        delegate?.musicPlayer(self, didChangeQueue: queue)
        log(.verbose, "queue after playNext \(describe(queue: queue))")
    }

    func addToQueue(_ item: PlayerItem) {
        log(.info, "addToQueue item=\(describe(item: item))")
        playbackQueue.append(item)
        delegate?.musicPlayer(self, didChangeQueue: queue)
        log(.verbose, "queue after addToQueue \(describe(queue: queue))")
    }

    func addToQueue(_ items: [PlayerItem]) {
        guard !items.isEmpty else {
            log(.warning, "addToQueue ignored because items are empty")
            return
        }

        log(.info, "addToQueue count=\(items.count)")
        playbackQueue.append(items)
        delegate?.musicPlayer(self, didChangeQueue: queue)
        log(.verbose, "queue after addToQueue \(describe(queue: queue))")
    }

    func insertInQueue(_ item: PlayerItem, at index: Int) {
        log(.info, "insertInQueue index=\(index) item=\(describe(item: item))")
        playbackQueue.insert(item, at: index)
        if index == 0 { preloadNextItem() }
        delegate?.musicPlayer(self, didChangeQueue: queue)
        log(.verbose, "queue after insertInQueue \(describe(queue: queue))")
    }

    @discardableResult
    func removeFromQueue(at index: Int) -> PlayerItem? {
        log(.info, "removeFromQueue index=\(index)")
        let removed = playbackQueue.remove(at: index)
        if index == 0 { preloadNextItem() }
        delegate?.musicPlayer(self, didChangeQueue: queue)
        log(.verbose, "removeFromQueue removed=\(describe(item: removed)) queue=\(describe(queue: queue))")
        return removed
    }

    func removeFromQueue(id: String) {
        log(.info, "removeFromQueue id=\(id)")
        _ = playbackQueue.remove(id: id)
        preloadNextItem()
        delegate?.musicPlayer(self, didChangeQueue: queue)
        log(.verbose, "queue after removeFromQueue id=\(id) \(describe(queue: queue))")
    }

    func moveInQueue(from source: Int, to destination: Int) {
        log(.info, "moveInQueue source=\(source) destination=\(destination)")
        playbackQueue.move(from: source, to: destination)
        if source == 0 || destination == 0 { preloadNextItem() }
        delegate?.musicPlayer(self, didChangeQueue: queue)
        log(.verbose, "queue after moveInQueue \(describe(queue: queue))")
    }

    func clearUpcomingQueue() {
        log(.info, "clearUpcomingQueue requested")
        playbackQueue.clearUpcoming()
        engine.preloadNextItem(nil)
        delegate?.musicPlayer(self, didChangeQueue: queue)
        log(.verbose, "queue after clearUpcomingQueue \(describe(queue: queue))")
    }

    func replaceUpcomingQueue(_ items: [PlayerItem]) {
        log(.info, "replaceUpcomingQueue count=\(items.count)")
        playbackQueue.clearUpcoming()
        playbackQueue.append(items)
        preloadNextItem()
        delegate?.musicPlayer(self, didChangeQueue: queue)
        log(.verbose, "queue after replaceUpcomingQueue \(describe(queue: queue))")
    }

    func replaceQueue(items: [PlayerItem], startIndex: Int = 0) {
        guard !items.isEmpty else {
            log(.warning, "replaceQueue ignored because items are empty")
            return
        }

        log(.info, "replaceQueue count=\(items.count) startIndex=\(startIndex)")
        playbackQueue.replaceAll(items: items, startIndex: startIndex)
        loadAndPlay(playbackQueue.nowPlaying, reason: .natural)
    }

    func skipCurrentItem() {
        log(.verbose, "skipCurrentItem requested")
        next()
    }
}
