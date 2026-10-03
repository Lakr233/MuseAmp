import Combine
import UIKit

extension LyricTimelineView {
    nonisolated struct ParsedLyrics: Sendable, Equatable {
        let lines: [String]
        let timeline: LyricTimeline?

        static let empty = ParsedLyrics(lines: [], timeline: nil)
    }

    nonisolated enum LyricsPhase: Sendable, Equatable {
        /// Just switched tracks; nothing is shown yet so a fast cache hit
        /// does not flash a loading message.
        case pending
        /// Still waiting for lyrics after `Layout.loadingIndicatorDelay`.
        case loading
        /// Every attempt failed; distinct from a track that has no lyrics.
        case failed
        case loaded(ParsedLyrics)
    }

    func bindDataSource() {
        let lyricsService = environment.lyricsService
        let lyricsReloadPublisher = NotificationCenter.default.publisher(for: .lyricsDidUpdate)
            .receive(on: DispatchQueue.main)
            .compactMap { [weak self] notification -> String? in
                guard let self else { return nil }
                let trackIDs = (notification.userInfo?[AppNotificationUserInfoKey.trackIDs] as? [String]) ?? []
                guard let currentTrackID = environment.playbackController.snapshot.currentTrack?.id,
                      trackIDs.contains(currentTrackID)
                else {
                    return nil
                }
                AppLog.info(self, "lyricsDidUpdate matched current track trackID=\(currentTrackID)")
                return currentTrackID
            }
            .map(Optional.some)

        let phase = environment.playbackController.$snapshot
            .map(\.currentTrack?.id)
            .removeDuplicates()
            .merge(with: lyricsReloadPublisher)
            .map { [weak self] trackID -> AnyPublisher<LyricsPhase, Never> in
                AppLog.info(self ?? "LyricTimelineView", "trackID changed trackID=\(trackID ?? "nil")")
                guard let trackID else {
                    return Just(LyricsPhase.loaded(.empty)).eraseToAnyPublisher()
                }
                var loadTask: Task<Void, Never>?
                // A Future replays its result, so the loading indicator below
                // sees it even when the load finishes before it subscribes.
                let load = Future<LyricsPhase, Never> { promise in
                    loadTask = Task {
                        await promise(.success(Self.loadPhase(for: trackID, using: lyricsService)))
                    }
                }
                let loadingIndicator = Just(LyricsPhase.loading)
                    .delay(for: .seconds(Layout.loadingIndicatorDelay), scheduler: DispatchQueue.main)
                    .prefix(untilOutputFrom: load)
                return load
                    .merge(with: loadingIndicator)
                    .prepend(.pending)
                    .handleEvents(receiveCancel: { loadTask?.cancel() })
                    .eraseToAnyPublisher()
            }
            .switchToLatest()

        // A track change must invalidate the previous track's cached playback
        // time, otherwise the first snapshot of the new song is built against
        // the old song's position and the list parks at the bottom.
        let playbackTime = environment.playbackController.playbackTimeSubject
            .map(\.currentTime)
            .merge(
                with: environment.playbackController.$snapshot
                    .map(\.currentTrack?.id)
                    .removeDuplicates()
                    .map { _ in TimeInterval.zero },
            )

        let dataSource = phase
            .combineLatest(playbackTime)
            .receive(on: DispatchQueue.main)
            .map { phase, currentTime in
                (phase, Self.buildSnapshot(phase: phase, currentTime: currentTime))
            }

        dataSource
            .removeDuplicates { $0.0 == $1.0 && $0.1 == $1.1 }
            .sink { [weak self] phase, snapshot in
                guard let self else { return }
                AppLog.verbose(self, "snapshot received itemCount=\(snapshot.items.count)")
                if case let .loaded(parsed) = phase {
                    renderedTimeline = parsed.timeline
                } else {
                    renderedTimeline = nil
                }
                applySnapshot(snapshot)
                focusSubject.send()
            }
            .store(in: &cancellables)

        interactionSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self else { return }
                AppLog.verbose(self, "user interaction received, suppressing programmatic scroll for \(Layout.userInteractionCooldown)s")
                userInteractionDeadline = Date().addingTimeInterval(Layout.userInteractionCooldown)
                Interface.animate(duration: 0.25) {
                    self.topBlurView.alpha = 0
                    self.bottomBlurView.alpha = 0
                }
            }
            .store(in: &cancellables)

        interactionSubject
            .delay(for: .seconds(Layout.userInteractionCooldown + 0.1), scheduler: DispatchQueue.main)
            .sink { [weak self] in
                guard let self else { return }
                guard !isProgrammaticScrollSuppressed else {
                    AppLog.verbose(self, "blur restore skipped, still suppressed")
                    return
                }
                // A finger resting on the list sends no scroll events; the
                // end of the drag sends a fresh interaction instead.
                guard !tableView.isTracking, !tableView.isDragging, !tableView.isDecelerating else {
                    AppLog.verbose(self, "blur restore skipped, user still scrolling")
                    return
                }
                AppLog.verbose(self, "blur restore animating alpha back to 1")
                Interface.animate(duration: 1.0) {
                    self.topBlurView.alpha = 1
                    self.bottomBlurView.alpha = 1
                }
                // Nothing else re-anchors the list while the active line stays
                // the same (last line, long gap, paused), so return to it now.
                focusCurrentLine(isUserInitialed: false)
            }
            .store(in: &cancellables)

        focusSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.focusCurrentLine(isUserInitialed: false)
            }
            .store(in: &cancellables)

        // Rows report their real height only once laid out, so the active
        // line is first anchored against estimated heights and then moves
        // when the rows above it are measured. Anchor it again each time.
        tableView.publisher(for: \.contentSize, options: [.new])
            .map(\.height)
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.focusSubject.send()
            }
            .store(in: &cancellables)
    }

    nonisolated static func parseLyrics(from lyricsText: String?) -> ParsedLyrics {
        guard let trimmed = lyricsText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else {
            return .empty
        }

        let converted = if AppPreferences.isLyricsAutoConvertChineseEnabled {
            LyricsChineseScriptConverter.convertToSystemScript(trimmed)
        } else {
            trimmed
        }

        let timeline = LyricTimeline(lrc: converted)

        if timeline.isSynced {
            return ParsedLyrics(lines: timeline.lines.map(\.text), timeline: timeline)
        }

        if !timeline.lines.isEmpty {
            let untimedLines = timeline.lines.map(\.text).filter { !$0.isEmpty }
            return ParsedLyrics(lines: untimedLines, timeline: nil)
        }

        return ParsedLyrics(lines: LyricParser.plainLines(from: converted), timeline: nil)
    }

    static func loadPhase(for trackID: String, using lyricsService: LyricsService) async -> LyricsPhase {
        do {
            let text = try await lyricsService.loadLyricsRetrying(for: trackID)
            let parsed = parseLyrics(from: text)
            AppLog.info("LyricTimelineView", "lyrics fetched trackID=\(trackID) lines=\(parsed.lines.count) timeline=\(parsed.timeline != nil)")
            return .loaded(parsed)
        } catch is CancellationError {
            AppLog.verbose("LyricTimelineView", "lyrics fetch cancelled trackID=\(trackID)")
            return .pending
        } catch {
            AppLog.error("LyricTimelineView", "lyrics fetch failed trackID=\(trackID) error=\(error)")
            return .failed
        }
    }

    nonisolated struct Snapshot: Sendable, Equatable {
        let items: [Item]
    }

    nonisolated static func buildSnapshot(phase: LyricsPhase, currentTime: TimeInterval) -> Snapshot {
        switch phase {
        case .pending:
            return Snapshot(items: [
                .spacer(Layout.topContentInset),
                .spacer(Layout.bottomContentInset),
            ])
        case .loading:
            return messageSnapshot(String(localized: "Fetching lyrics…"))
        case .failed:
            return messageSnapshot(String(localized: "Unable to load lyrics"))
        case let .loaded(lyrics):
            guard !lyrics.lines.isEmpty else {
                return messageSnapshot(String(localized: "No lyrics available"))
            }

            var items: [Item] = [.spacer(Layout.topContentInset)]
            if let timeline = lyrics.timeline {
                let activeRange = timeline.activeLineRange(at: currentTime)
                for (index, text) in lyrics.lines.enumerated() {
                    items.append(.line(index, text, activeRange?.contains(index) ?? false))
                }
            } else {
                for (index, text) in lyrics.lines.enumerated() {
                    items.append(.staticLine(index, text))
                }
            }
            items.append(.spacer(Layout.bottomContentInset))
            return Snapshot(items: items)
        }
    }

    private nonisolated static func messageSnapshot(_ message: String) -> Snapshot {
        Snapshot(items: [
            .spacer(Layout.topContentInset),
            .message(message),
            .spacer(Layout.bottomContentInset),
        ])
    }
}
