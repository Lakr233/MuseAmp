//
//  NowPlayingCompactController.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import AmMusicKit
import AmMusicPlayerKit
import Combine
import ConfigurableKit
import LNPopupController
import LRUCache
import SnapKit
import Then
import UIKit

func shouldCacheUnavailableLyricsResult(for error: any Error) -> Bool {
    guard let apiError = error as? APIError else {
        return false
    }

    guard case let .requestFailed(statusCode) = apiError else {
        return false
    }

    return statusCode == 404
}

class NowPlayingCompactController: UIViewController {
    let environment: AppEnvironment
    let backgroundView = NowPlayingArtworkBackgroundView()
    let pageViewController = NowPlayingCompactPageController()
    let controlIslandViewModel = NowPlayingControlIslandViewModel()
    let routePickerPresenter = NowPlayingRoutePickerPresenter()
    var cancellables: Set<AnyCancellable> = []
    var artworkPaletteTask: Task<Void, Never>?
    var lyricsTask: Task<Void, Never>?
    var queueShuffleFeedbackTask: Task<Void, Never>?
    var isQueueShuffleFeedbackActive = false
    var lastBackgroundSource: NowPlayingControlIslandViewModel.BackgroundSource = .idle
    var lastPresentedTrackID: String?
    var lastPresentedArtworkURL: URL?
    var currentPlaybackSnapshot = PlaybackSnapshot.empty
    lazy var idleBackgroundColors = Self.makeIdleBackgroundColors()
    var artworkPaletteCache = LRUCache<String, [UIColor]>(countLimit: 32)
    var lyricsCache: [String: String] = [:]
    var lyricsRawCache: [String: String] = [:]
    var lyricsLoadingTrackID: String?
    var lyricsTransientFailureTrackID: String?
    private var didEnterBackgroundObserver: NSObjectProtocol?
    private var didBecomeActiveObserver: NSObjectProtocol?
    private(set) var isInterfaceSuspended = false

    init(environment: AppEnvironment) {
        self.environment = environment
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        installBackgroundView()
        installPageViewController()
        bindQueueSectionActions()
        bindViewModelActions()
        bindContentSelector()
        bindQueueSnapshot()
        bindApplicationLifecycle()
        bindLyricsChineseConvertPreference()
        bindCleanSongTitlePreference()
        applyInitialPlaybackPresentation()
        bindPlaybackSnapshot()
        bindPlaybackTime()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updatePopupCloseButtonAppearance(for: controlIslandViewModel.selectedContentSelector)
        Interface.smoothSpringAnimate {
            self.pageViewController.view.transform = .identity
            var candidates: [UIView] = [self.view]
            while let first = candidates.first {
                candidates.removeFirst()
                candidates.append(contentsOf: first.subviews)
                first.transform = .identity
                first.setNeedsLayout()
            }
            self.view.layoutIfNeeded()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
    }

    override var prefersStatusBarHidden: Bool {
        true
    }

    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation {
        .fade
    }

    override func viewForPopupTransition(
        from _: UIViewController.PopupPresentationState,
        to _: UIViewController.PopupPresentationState,
    ) -> UIView? {
        nil
    }

    deinit {
        artworkPaletteTask?.cancel()
        lyricsTask?.cancel()
        queueShuffleFeedbackTask?.cancel()
        if let didEnterBackgroundObserver {
            NotificationCenter.default.removeObserver(didEnterBackgroundObserver)
        }
        if let didBecomeActiveObserver {
            NotificationCenter.default.removeObserver(didBecomeActiveObserver)
        }
    }

    // MARK: - Control Actions

    func play() {
        environment.playbackController.play()
    }

    func pause() {
        environment.playbackController.pause()
    }

    func togglePlayPause() {
        environment.playbackController.togglePlayPause()
    }

    func next() {
        environment.playbackController.next()
    }

    func previous() {
        environment.playbackController.previous()
    }

    func seek(to seconds: TimeInterval) {
        environment.playbackController.seek(to: seconds)
    }

    func setShuffle(_ enabled: Bool) {
        environment.playbackController.setShuffle(enabled)
    }

    func setRepeatMode(_ mode: RepeatMode) {
        environment.playbackController.setRepeatMode(mode)
    }

    func bindQueueSectionActions() {
        pageViewController.onToggleQueueShuffle = { [weak self] in
            self?.shuffleQueueOnce()
        }

        pageViewController.onSelectQueueTrack = { [weak self] selection in
            guard let self else { return }
            switch selection {
            case let .queue(index):
                environment.playbackController.skipToQueueTrack(at: index)
            }
        }

        pageViewController.onRemoveQueueTrack = { [weak self] queueIndex in
            self?.environment.playbackController.removeFromQueue(at: queueIndex)
        }

        pageViewController.onRestartCurrentTrack = { [weak self] in
            self?.environment.playbackController.restartCurrentTrack()
        }

        pageViewController.onPlayFromHere = { [weak self] queueIndex in
            self?.environment.playbackController.skipToQueueTrack(at: queueIndex)
        }

        pageViewController.onPlayNext = { [weak self] track in
            guard let self else { return }
            Task {
                _ = await self.environment.playbackController.playNext([track])
            }
        }

        pageViewController.onCycleQueueRepeatMode = { [weak self] in
            guard let self else { return }
            let nextMode: RepeatMode = switch currentPlaybackSnapshot.repeatMode {
            case .off:
                .queue
            case .queue:
                .track
            case .track:
                .off
            }
            setRepeatMode(nextMode)
        }
    }

    func shuffleQueueOnce() {
        guard !currentPlaybackSnapshot.upcoming.isEmpty else {
            return
        }

        queueShuffleFeedbackTask?.cancel()
        isQueueShuffleFeedbackActive = true
        pageViewController.setQueueShuffleFeedbackActive(true)

        Task { [weak self] in
            await self?.environment.playbackController.shuffleUpcomingQueue()
        }

        queueShuffleFeedbackTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled, let self else {
                return
            }
            isQueueShuffleFeedbackActive = false
            pageViewController.setQueueShuffleFeedbackActive(false)
        }
    }

    func bindApplicationLifecycle() {
        didEnterBackgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main,
        ) { [weak self] _ in
            self?.setInterfaceSuspended(true)
        }

        didBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main,
        ) { [weak self] _ in
            self?.setInterfaceSuspended(false)
        }

        setInterfaceSuspended(UIApplication.shared.applicationState != .active)
    }

    func setInterfaceSuspended(_ suspended: Bool) {
        guard isInterfaceSuspended != suspended else {
            return
        }

        isInterfaceSuspended = suspended
        pageViewController.setInterfaceSuspended(suspended)
        backgroundView.setAnimationSuspended(suspended)

        if suspended {
            artworkPaletteTask?.cancel()
            artworkPaletteTask = nil
            lyricsTask?.cancel()
            lyricsTask = nil
            queueShuffleFeedbackTask?.cancel()
            queueShuffleFeedbackTask = nil
            isQueueShuffleFeedbackActive = false
            pageViewController.setQueueShuffleFeedbackActive(false)
            return
        }

        refreshControlIslandContent(animated: false)
        refreshPlayingContent(animated: false)
    }

    // MARK: - Lyrics

    func processedLyrics(_ text: String) -> String {
        guard !text.isEmpty, AppPreferences.isLyricsAutoConvertChineseEnabled else {
            return text
        }
        return LyricsChineseScriptConverter.convertToSystemScript(text)
    }

    func cacheLyrics(_ text: String, for trackID: String) {
        lyricsRawCache[trackID] = text
        lyricsCache[trackID] = processedLyrics(text)
    }

    func reprocessAllCachedLyrics() {
        for (trackID, raw) in lyricsRawCache {
            lyricsCache[trackID] = processedLyrics(raw)
        }
        guard let trackID = currentPlaybackSnapshot.currentTrack?.id,
              let lyrics = lyricsCache[trackID]
        else { return }
        pageViewController.updateLyrics(
            text: lyrics.isEmpty ? nil : lyrics,
            isLoading: false,
            currentTime: currentPlaybackSnapshot.currentTime,
        )
    }

    func bindLyricsChineseConvertPreference() {
        ConfigurableKit.publisher(
            forKey: AppPreferences.lyricsAutoConvertChineseKey,
            type: Bool.self,
        )
        .dropFirst()
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
            self?.reprocessAllCachedLyrics()
        }
        .store(in: &cancellables)
    }

    func bindCleanSongTitlePreference() {
        ConfigurableKit.publisher(
            forKey: AppPreferences.cleanSongTitleKey, type: Bool.self,
        )
        .dropFirst()
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
            guard let self else { return }
            let snapshot = environment.playbackController.snapshot
            let presentation = controlIslandViewModel.apply(snapshot: snapshot)
            pageViewController.configureTransport(
                with: presentation.content,
                animated: false,
            )
        }
        .store(in: &cancellables)
    }

    func loadLyrics(for trackID: String) {
        if let lyrics = lyricsCache[trackID] {
            AppLog.info(
                self,
                "loadLyrics refresh source=memory-cache trackID=\(trackID) \(nowPlayingLogTextSummary(lyrics))",
            )
            lyricsLoadingTrackID = nil
            if lyricsTransientFailureTrackID == trackID {
                lyricsTransientFailureTrackID = nil
            }
            pageViewController.updateLyrics(
                text: lyrics.isEmpty ? nil : lyrics,
                isLoading: false,
                currentTime: currentPlaybackSnapshot.currentTime,
            )
            return
        }

        if let storedLyrics = environment.lyricsService.cachedLyrics(for: trackID) {
            AppLog.info(
                self,
                "loadLyrics refresh source=offline-cache trackID=\(trackID) \(nowPlayingLogTextSummary(storedLyrics))",
            )
            lyricsLoadingTrackID = nil
            if lyricsTransientFailureTrackID == trackID {
                lyricsTransientFailureTrackID = nil
            }
            cacheLyrics(storedLyrics, for: trackID)
            let cached = lyricsCache[trackID] ?? storedLyrics
            pageViewController.updateLyrics(
                text: cached.isEmpty ? nil : cached,
                isLoading: false,
                currentTime: currentPlaybackSnapshot.currentTime,
            )
            return
        }

        if lyricsTransientFailureTrackID == trackID {
            AppLog.info(
                self,
                "loadLyrics refresh source=transient-failure trackID=\(trackID)",
            )
            lyricsLoadingTrackID = nil
            pageViewController.updateLyrics(
                text: nil,
                isLoading: false,
                currentTime: currentPlaybackSnapshot.currentTime,
            )
            return
        }

        if lyricsLoadingTrackID == trackID {
            AppLog.verbose(
                self,
                "loadLyrics refresh source=in-flight trackID=\(trackID)",
            )
            pageViewController.updateLyrics(
                text: nil,
                isLoading: true,
                currentTime: currentPlaybackSnapshot.currentTime,
            )
            return
        }

        if let pendingTrackID = lyricsLoadingTrackID,
           pendingTrackID != trackID
        {
            AppLog.info(
                self,
                "loadLyrics refresh cancel pendingTrackID=\(pendingTrackID) nextTrackID=\(trackID)",
            )
        }
        lyricsTask?.cancel()
        lyricsLoadingTrackID = trackID
        AppLog.info(self, "loadLyrics refresh source=network-start trackID=\(trackID)")
        pageViewController.updateLyrics(
            text: nil,
            isLoading: true,
            currentTime: currentPlaybackSnapshot.currentTime,
        )

        lyricsTask = Task { [weak self] in
            guard let self else { return }
            do {
                let lyrics = try await environment.lyricsService.fetchLyrics(for: trackID)
                guard !Task.isCancelled else { return }
                let normalizedLyrics = lyrics.trimmingCharacters(in: .whitespacesAndNewlines)
                environment.lyricsService.persistLyricsIfDownloaded(normalizedLyrics, for: trackID)

                await MainActor.run { [weak self] in
                    guard let self else { return }
                    lyricsLoadingTrackID = nil
                    if lyricsTransientFailureTrackID == trackID {
                        lyricsTransientFailureTrackID = nil
                    }
                    cacheLyrics(normalizedLyrics, for: trackID)
                    AppLog.info(
                        self,
                        "loadLyrics refresh source=network-success trackID=\(trackID) \(nowPlayingLogTextSummary(normalizedLyrics))",
                    )
                    guard currentPlaybackSnapshot.currentTrack?.id == trackID,
                          controlIslandViewModel.selectedContentSelector == .lyrics
                    else {
                        return
                    }
                    let cached = lyricsCache[trackID] ?? normalizedLyrics
                    pageViewController.updateLyrics(
                        text: cached.isEmpty ? nil : cached,
                        isLoading: false,
                        currentTime: currentPlaybackSnapshot.currentTime,
                    )
                }
            } catch {
                guard !Task.isCancelled else { return }
                let shouldCacheUnavailableResult = shouldCacheUnavailableLyricsResult(for: error)
                if shouldCacheUnavailableResult {
                    environment.lyricsService.persistLyricsIfDownloaded("", for: trackID)
                }

                await MainActor.run { [weak self] in
                    guard let self else { return }
                    lyricsLoadingTrackID = nil
                    if shouldCacheUnavailableResult {
                        if lyricsTransientFailureTrackID == trackID {
                            lyricsTransientFailureTrackID = nil
                        }
                        lyricsRawCache[trackID] = ""
                        lyricsCache[trackID] = ""
                    } else {
                        lyricsTransientFailureTrackID = trackID
                    }
                    guard currentPlaybackSnapshot.currentTrack?.id == trackID,
                          controlIslandViewModel.selectedContentSelector == .lyrics
                    else {
                        return
                    }
                    pageViewController.updateLyrics(
                        text: nil,
                        isLoading: false,
                        currentTime: currentPlaybackSnapshot.currentTime,
                    )
                    if shouldCacheUnavailableResult {
                        AppLog.info(self, "loadLyrics refresh source=network-unavailable trackID=\(trackID)")
                    } else {
                        AppLog.error(self, "loadLyrics refresh source=network-failure trackID=\(trackID) error=\(error)")
                    }
                }
            }
        }
    }

    private func installBackgroundView() {
        view.addSubview(backgroundView)
        backgroundView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        backgroundView.apply(colors: idleBackgroundColors)
    }

    private func installPageViewController() {
        pageViewController.onArtworkLoaded = { [weak self] url, image in
            guard let self else { return }
            updateArtworkBackgroundFromDisplayedArtwork(url: url, image: image)
            guard currentPlaybackSnapshot.currentTrack?.artworkURL == url else { return }
            popupItem.image = image
        }
        pageViewController.onSeekToLyricsTime = { [weak self] seconds in
            self?.seek(to: seconds)
            self?.play()
        }
        pageViewController.onCopyAllLyrics = { lyrics in
            UIPasteboard.general.string = lyrics.joined(separator: "\n")
            AppLog.info("NowPlayingCompactController", "copyAllLyrics count=\(lyrics.count)")
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        pageViewController.onManageLyrics = { [weak self] lyrics, activeIndex in
            self?.presentLyricSelectionSheet(with: lyrics, activeIndex: activeIndex)
        }
        pageViewController.onPageChanged = { [weak self] selector in
            self?.controlIslandViewModel.setContentSelector(selector)
        }
        pageViewController.bindTransport(to: controlIslandViewModel)
        pageViewController.installRoutePickerView(routePickerPresenter.routePickerView)

        addChild(pageViewController)
        view.addSubview(pageViewController.view)
        pageViewController.view.accessibilityIdentifier = "nowplaying.pages"
        pageViewController.view.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        pageViewController.didMove(toParent: self)
    }

    func prepareForPopupOpen() {
        AppLog.info(self, "prepareForPopupOpen isPlaying=\(currentPlaybackSnapshot.state == .playing)")
        loadViewIfNeeded()
        updatePopupCloseButtonAppearance(for: controlIslandViewModel.selectedContentSelector)
        refreshPlayingContent(animated: false)
        let presentation = controlIslandViewModel.apply(snapshot: currentPlaybackSnapshot)
        updateArtworkBackground(
            using: presentation.backgroundSource,
            animated: false,
        )
        pageViewController.ensureCurrentPageIsLaidOut()
    }

    func updatePopupCloseButtonAppearance(for _: NowPlayingControlIslandViewModel.ContentSelector) {
        let popupContentView = popupPresentationContainer?.popupContentView
        popupContentView?.popupCloseButtonStyle = .none
        popupContentView?.popupCloseButton.isHidden = true
    }
}
