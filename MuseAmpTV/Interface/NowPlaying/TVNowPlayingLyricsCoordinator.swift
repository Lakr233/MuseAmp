//
//  TVNowPlayingLyricsCoordinator.swift
//  MuseAmpTV
//
//  Slim lyrics loader for the tvOS Now Playing page. Ported from
//  MuseAmp/Interface/NowPlaying/Support/NowPlayingLyricsCoordinator.swift
//  with AppEnvironment / ConfigurableKit / Chinese-conversion plumbing removed.
//

import Foundation

@MainActor
final class TVNowPlayingLyricsCoordinator {
    private let lyricsService: LyricsService
    private let shouldApplyLoadedLyrics: (String) -> Bool
    private let updateLyricsView: (String?, Bool) -> Void

    private var lyricsTask: Task<Void, Never>?
    private var lyricsCache: [String: String] = [:]
    private var lyricsLoadingTrackID: String?

    init(
        lyricsService: LyricsService,
        shouldApplyLoadedLyrics: @escaping (String) -> Bool,
        updateLyricsView: @escaping (String?, Bool) -> Void,
    ) {
        self.lyricsService = lyricsService
        self.shouldApplyLoadedLyrics = shouldApplyLoadedLyrics
        self.updateLyricsView = updateLyricsView
    }

    deinit {
        lyricsTask?.cancel()
    }

    func clearDisplayedLyrics() {
        lyricsTask?.cancel()
        lyricsTask = nil
        lyricsLoadingTrackID = nil
        updateLyricsView(nil, false)
    }

    func loadLyrics(for trackID: String) {
        if let lyrics = lyricsCache[trackID] ?? lyricsService.cachedLyrics(for: trackID) {
            lyricsLoadingTrackID = nil
            lyricsCache[trackID] = lyrics
            updateLyricsView(nil, true)
            lyricsTask = Task { @MainActor [weak self] in
                guard let self else { return }
                guard !Task.isCancelled else { return }
                updateLyricsView(lyrics.isEmpty ? nil : lyrics, false)
            }
            return
        }

        if lyricsLoadingTrackID == trackID {
            updateLyricsView(nil, true)
            return
        }

        lyricsTask?.cancel()
        lyricsLoadingTrackID = trackID
        updateLyricsView(nil, true)

        lyricsTask = Task { [weak self] in
            guard let self else { return }
            do {
                let lyrics = try await lyricsService.fetchLyrics(for: trackID)
                guard !Task.isCancelled else { return }
                let normalized = lyrics.trimmingCharacters(in: .whitespacesAndNewlines)
                lyricsService.persistLyricsIfDownloaded(normalized, for: trackID)

                await MainActor.run { [weak self] in
                    guard let self else { return }
                    lyricsLoadingTrackID = nil
                    lyricsCache[trackID] = normalized
                    guard shouldApplyLoadedLyrics(trackID) else { return }
                    updateLyricsView(normalized.isEmpty ? nil : normalized, false)
                    AppLog.info(self, "loadLyrics success trackID=\(trackID) length=\(normalized.count)")
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    lyricsLoadingTrackID = nil
                    guard shouldApplyLoadedLyrics(trackID) else { return }
                    updateLyricsView(nil, false)
                    AppLog.error(self, "loadLyrics failed trackID=\(trackID) error=\(error)")
                }
            }
        }
    }
}
