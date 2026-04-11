//
//  NowPlayingRelaxedController.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import AmMusicPlayerKit
import Combine
import ConfigurableKit
import DominantColors
import Kingfisher
import LNPopupController
import LRUCache
import SnapKit
import Then
import UIKit

class NowPlayingRelaxedController: UIViewController {
    let environment: AppEnvironment
    let backgroundView = NowPlayingArtworkBackgroundView()
    let controlIslandViewModel = NowPlayingControlIslandViewModel()
    let routePickerPresenter = NowPlayingRoutePickerPresenter()

    // MARK: - Section Views

    let relaxedTransportView = NowPlayingRelaxedTransportView()
    lazy var centerSectionView = NowPlayingCenterSectionView(transportView: relaxedTransportView)
    let lyricSectionView = NowPlayingLyricSectionView()
    let listSectionView = NowPlayingListSectionView()

    // MARK: - Right Panel

    enum RightPanel {
        case lyrics
        case queue
    }

    private(set) var currentRightPanel: RightPanel = .lyrics

    private let rightPanelContentContainer = UIView().then {
        $0.backgroundColor = .clear
        $0.clipsToBounds = false
    }

    // MARK: - Layout Containers

    private let contentSafeAreaView = UIView().then {
        $0.backgroundColor = .clear
        $0.isUserInteractionEnabled = true
    }

    private let leftPanelView = UIView().then {
        $0.backgroundColor = .clear
        $0.clipsToBounds = true
    }

    private let rightPanelView = UIView().then {
        $0.backgroundColor = .clear
        $0.clipsToBounds = false
    }

    // MARK: - State

    var cancellables: Set<AnyCancellable> = []
    var artworkPaletteTask: Task<Void, Never>?
    var lyricsTask: Task<Void, Never>?
    var queueShuffleFeedbackTask: Task<Void, Never>?
    var isQueueShuffleFeedbackActive = false
    var lastBackgroundSource: NowPlayingControlIslandViewModel.BackgroundSource = .idle
    var lastPresentedTrackID: String?
    var lastPresentedArtworkURL: URL?
    var currentPlaybackSnapshot = PlaybackSnapshot.empty
    let idleBackgroundColors: [UIColor] = [
        UIColor(white: 0.45, alpha: 1),
        UIColor(white: 0.50, alpha: 1),
        UIColor(white: 0.52, alpha: 1),
        UIColor(white: 0.48, alpha: 1),
    ]
    var artworkPaletteCache = LRUCache<String, [UIColor]>(countLimit: 32)
    var lyricsCache: [String: String] = [:]
    var lyricsRawCache: [String: String] = [:]
    var lyricsLoadingTrackID: String?
    var lyricsTransientFailureTrackID: String?
    private(set) var isInterfaceSuspended = false

    private var didEnterBackgroundObserver: NSObjectProtocol?
    private var didBecomeActiveObserver: NSObjectProtocol?

    // MARK: - Lifecycle

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
        installContentLayout()
        installLeftPanel()
        installRightPanel()
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

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateContentSafeAreaFrame()
    }

    override var prefersStatusBarHidden: Bool {
        false
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        .lightContent
    }

    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation {
        .fade
    }

    override var keyCommands: [UIKeyCommand]? {
        [UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(escapeKeyPressed))]
    }

    @objc private func escapeKeyPressed() {
        popupPresentationContainer?.closePopup(animated: true)
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

    // MARK: - Background Setup

    private func installBackgroundView() {
        view.addSubview(backgroundView)
        backgroundView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        backgroundView.apply(colors: idleBackgroundColors)
    }

    // MARK: - Content Layout

    private func installContentLayout() {
        view.addSubview(contentSafeAreaView)
        contentSafeAreaView.snp.makeConstraints { make in
            make.top.bottom.trailing.equalToSuperview()
            make.leading.equalToSuperview()
        }
        contentSafeAreaView.addSubview(leftPanelView)
        contentSafeAreaView.addSubview(rightPanelView)

        leftPanelView.snp.makeConstraints { make in
            make.leading.top.bottom.equalToSuperview()
            make.width.equalToSuperview().multipliedBy(0.5)
        }

        rightPanelView.snp.makeConstraints { make in
            make.trailing.top.bottom.equalToSuperview()
            make.width.equalToSuperview().multipliedBy(0.5)
        }
    }

    private func installLeftPanel() {
        centerSectionView.onArtworkLoaded = { [weak self] url, image in
            guard let self else { return }
            updateArtworkBackgroundFromDisplayedArtwork(url: url, image: image)
            guard currentPlaybackSnapshot.currentTrack?.artworkURL == url else { return }
            popupItem.image = image
        }
        centerSectionView.bindTransport(to: controlIslandViewModel)
        centerSectionView.installRoutePickerView(routePickerPresenter.routePickerView)

        leftPanelView.addSubview(centerSectionView)
        centerSectionView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        relaxedTransportView.segmentedControl.addTarget(
            self,
            action: #selector(segmentedControlChanged(_:)),
            for: .valueChanged,
        )
    }

    private func installRightPanel() {
        rightPanelView.addSubview(rightPanelContentContainer)

        rightPanelContentContainer.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        lyricSectionView.onSeekToLineTime = { [weak self] seconds in
            self?.seek(to: seconds)
            self?.play()
        }
        lyricSectionView.onCopyAllLyrics = { lyrics in
            UIPasteboard.general.string = lyrics.joined(separator: "\n")
            AppLog.info("NowPlayingRelaxedController", "copyAllLyrics count=\(lyrics.count)")
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        lyricSectionView.onRequestManageLyrics = { [weak self] lyrics, activeIndex in
            self?.presentLyricSelectionSheet(with: lyrics, activeIndex: activeIndex)
        }

        rightPanelContentContainer.addSubview(lyricSectionView)
        rightPanelContentContainer.addSubview(listSectionView)

        lyricSectionView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        listSectionView.snp.makeConstraints { make in
            make.top.bottom.equalToSuperview()
            make.leading.trailing.equalToSuperview().inset(16)
        }

        listSectionView.alpha = 0
        listSectionView.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
    }

    @objc private func segmentedControlChanged(_ sender: UISegmentedControl) {
        let panel: RightPanel = sender.selectedSegmentIndex == 0 ? .lyrics : .queue
        switchRightPanel(to: panel, animated: true)

        let selector: NowPlayingControlIslandViewModel.ContentSelector = panel == .lyrics ? .lyrics : .queue
        controlIslandViewModel.setContentSelector(selector)
    }

    // MARK: - Right Panel Toggle

    func switchRightPanel(to panel: RightPanel, animated: Bool) {
        guard panel != currentRightPanel else { return }
        currentRightPanel = panel

        let incomingView: UIView
        let outgoingView: UIView

        switch panel {
        case .lyrics:
            incomingView = lyricSectionView
            outgoingView = listSectionView
            relaxedTransportView.segmentedControl.selectedSegmentIndex = 0
        case .queue:
            incomingView = listSectionView
            outgoingView = lyricSectionView
            relaxedTransportView.segmentedControl.selectedSegmentIndex = 1
        }

        guard animated else {
            outgoingView.alpha = 0
            outgoingView.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
            incomingView.alpha = 1
            incomingView.transform = .identity
            return
        }

        incomingView.alpha = 0
        incomingView.transform = CGAffineTransform(scaleX: 1.04, y: 1.04)

        Interface.springAnimate(
            duration: 0.35,
            dampingRatio: 0.92,
            initialVelocity: 0.8,
        ) {
            outgoingView.alpha = 0
            outgoingView.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
            incomingView.alpha = 1
            incomingView.transform = .identity
        }
    }

    // MARK: - Popup

    func prepareForPopupOpen() {
        AppLog.info(self, "prepareForPopupOpen isPlaying=\(currentPlaybackSnapshot.state == .playing)")
        loadViewIfNeeded()
        refreshPlayingContent(animated: false)
        let presentation = controlIslandViewModel.apply(snapshot: currentPlaybackSnapshot)
        updateArtworkBackground(
            using: presentation.backgroundSource,
            animated: false,
        )

        let popupContentView = popupPresentationContainer?.popupContentView
        popupContentView?.popupCloseButtonStyle = .none
        popupContentView?.popupCloseButton.isHidden = true
    }

    // MARK: - Background

    func makeBackgroundSource(
        from snapshot: PlaybackSnapshot,
    ) -> NowPlayingControlIslandViewModel.BackgroundSource {
        guard let artworkURL = snapshot.currentTrack?.artworkURL else {
            return .idle
        }
        return .artwork(url: artworkURL)
    }

    func updateArtworkBackground(
        using backgroundSource: NowPlayingControlIslandViewModel.BackgroundSource,
        animated: Bool,
    ) {
        switch (lastBackgroundSource, backgroundSource) {
        case let (.artwork(previousURL), .artwork(currentURL)):
            if previousURL == currentURL,
               artworkPaletteCache.value(forKey: currentURL.absoluteString) != nil
            {
                return
            }
        case (.idle, .idle):
            return
        default:
            break
        }
        lastBackgroundSource = backgroundSource
        artworkPaletteTask?.cancel()

        switch backgroundSource {
        case .idle:
            backgroundView.apply(colors: idleBackgroundColors)
        case let .artwork(url):
            if let cachedColors = artworkPaletteCache.value(forKey: url.absoluteString) {
                backgroundView.apply(colors: cachedColors)
                return
            }

            artworkPaletteTask = Task { [weak self] in
                guard let self else { return }
                let colors = await paletteColors(for: url)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard self.lastBackgroundSource == backgroundSource else { return }
                    if let colors {
                        self.artworkPaletteCache.setValue(colors, forKey: url.absoluteString)
                        self.backgroundView.apply(colors: colors)
                    } else {
                        self.backgroundView.apply(colors: self.idleBackgroundColors)
                    }
                }
            }
        }
        _ = animated
    }

    func updateArtworkBackgroundFromDisplayedArtwork(url: URL, image: UIImage) {
        guard case let .artwork(currentURL) = lastBackgroundSource,
              currentURL == url
        else {
            return
        }

        if let cachedColors = artworkPaletteCache.value(forKey: url.absoluteString) {
            backgroundView.apply(colors: cachedColors)
            return
        }

        artworkPaletteTask?.cancel()
        artworkPaletteTask = Task { [weak self] in
            guard let self else { return }
            let colors = await extractPalette(from: image)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard self.currentPlaybackSnapshot.currentTrack?.artworkURL == url else { return }
                guard let colors else { return }
                self.artworkPaletteCache.setValue(colors, forKey: url.absoluteString)
                self.backgroundView.apply(colors: colors)
            }
        }
    }

    // MARK: - Palette

    func paletteColors(for artworkURL: URL) async -> [UIColor]? {
        guard let image = await retrieveArtworkImage(from: artworkURL) else {
            return nil
        }
        return await extractPalette(from: image)
    }

    func retrieveArtworkImage(from artworkURL: URL) async -> UIImage? {
        if artworkURL.isFileURL {
            return UIImage(contentsOfFile: artworkURL.path)
        }
        return await withCheckedContinuation { continuation in
            KingfisherManager.shared.retrieveImage(with: artworkURL) { result in
                switch result {
                case let .success(value):
                    continuation.resume(returning: value.image)
                case .failure:
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    func extractPalette(from image: UIImage) async -> [UIColor]? {
        let imageData = image.pngData() ?? image.jpegData(compressionQuality: 1)
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let imageData,
                      let decodedImage = UIImage(data: imageData)
                else {
                    continuation.resume(returning: nil)
                    return
                }
                let extracted = (try? DominantColors.dominantColors(
                    uiImage: decodedImage,
                    quality: .best,
                    maxCount: 4,
                    options: [.excludeBlack, .excludeWhite, .excludeGray],
                )) ?? []
                continuation.resume(returning: extracted)
            }
        }
    }

    // MARK: - Application Lifecycle

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
        guard isInterfaceSuspended != suspended else { return }
        isInterfaceSuspended = suspended
        backgroundView.setAnimationSuspended(suspended)
        centerSectionView.setAnimationsSuspended(suspended)
        lyricSectionView.setAnimationSuspended(suspended)

        if suspended {
            artworkPaletteTask?.cancel()
            artworkPaletteTask = nil
            lyricsTask?.cancel()
            lyricsTask = nil
            queueShuffleFeedbackTask?.cancel()
            queueShuffleFeedbackTask = nil
            isQueueShuffleFeedbackActive = false
            listSectionView.setShuffleFeedbackActive(false)
            return
        }

        refreshControlIslandContent(animated: false)
        refreshPlayingContent(animated: false)
    }

    // MARK: - Content Safe Area

    private func updateContentSafeAreaFrame() {
        let bounds = view.bounds
        var leadingInset: CGFloat = 0

        if let mainController = view.window?.rootViewController as? MainController {
            let split = mainController.rootSplitViewController
            let displayMode = split.displayMode
            if displayMode == .oneBesideSecondary || displayMode == .oneOverSecondary {
                let sidebarWidth = split.primaryColumnWidth
                let sidebarFrameInWindow = CGRect(x: 0, y: 0, width: sidebarWidth, height: bounds.height)
                let sidebarFrameInSelf = view.convert(sidebarFrameInWindow, from: nil)
                let overlap = sidebarFrameInSelf.intersection(bounds)
                if !overlap.isNull, overlap.width > 0 {
                    leadingInset = overlap.maxX
                }
            }
        }

        contentSafeAreaView.snp.updateConstraints { make in
            make.leading.equalToSuperview().offset(leadingInset)
        }
    }
}
