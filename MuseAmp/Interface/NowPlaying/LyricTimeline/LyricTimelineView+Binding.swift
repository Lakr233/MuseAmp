import Combine
import UIKit

extension LyricTimelineView {
    nonisolated struct ParsedLyrics: Sendable, Equatable {
        let lines: [String]
        let timeline: LyricTimeline?

        static let empty = ParsedLyrics(lines: [], timeline: nil)
    }

    nonisolated enum LyricsPhase: Sendable, Equatable {
        case pending
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
                let fetch = Deferred {
                    Future<LyricsPhase, any Error> { promise in
                        Task {
                            do {
                                let text = try await lyricsService.loadLyricsThrowing(for: trackID)
                                let parsed = Self.parseLyrics(from: text)
                                AppLog.info("LyricTimelineView", "lyrics fetched trackID=\(trackID) lines=\(parsed.lines.count) timeline=\(parsed.timeline != nil)")
                                promise(.success(.loaded(parsed)))
                            } catch {
                                AppLog.error("LyricTimelineView", "lyrics fetch failed trackID=\(trackID) error=\(error)")
                                promise(.failure(error))
                            }
                        }
                    }
                }
                .retry(2)
                .replaceError(with: LyricsPhase.loaded(.empty))
                return Just(LyricsPhase.pending)
                    .append(fetch)
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
                AppLog.verbose(self, "blur restore animating alpha back to 1")
                Interface.animate(duration: 1.0) {
                    self.topBlurView.alpha = 1
                    self.bottomBlurView.alpha = 1
                }
            }
            .store(in: &cancellables)

        focusSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.focusCurrentLine(isUserInitialed: false)
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

        if !timeline.lines.isEmpty {
            return ParsedLyrics(lines: timeline.lines.map(\.text), timeline: timeline)
        }

        let plainLines = converted
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        return ParsedLyrics(lines: plainLines, timeline: nil)
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
        case let .loaded(lyrics):
            guard !lyrics.lines.isEmpty else {
                return Snapshot(items: [
                    .spacer(Layout.topContentInset),
                    .message(String(localized: "No lyrics available")),
                    .spacer(Layout.bottomContentInset),
                ])
            }

            var items: [Item] = [.spacer(Layout.topContentInset)]
            if let timeline = lyrics.timeline {
                let activeIndex = timeline.progress(at: currentTime)?.index
                for (index, text) in lyrics.lines.enumerated() {
                    items.append(.line(index, text, index == activeIndex))
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
}
