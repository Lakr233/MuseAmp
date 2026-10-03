//
//  NowPlayingCompactController.swift
//  MuseAmp
//
//  Created by @Lakr233 on 2026/04/11.
//

import Combine
import LNPopupController
import MuseAmpPlayerKit
import SnapKit
import UIKit

class NowPlayingCompactController: UIViewController, NowPlayingQueueShellController, NowPlayingArtworkShellController, NowPlayingLifecycleShellController {
    let environment: AppEnvironment
    let backgroundView = NowPlayingArtworkBackgroundView()
    lazy var artworkBackgroundCoordinator = NowPlayingArtworkBackgroundCoordinator(
        backgroundView: backgroundView,
        logOwner: "NowPlayingCompactController",
        currentArtworkURL: { [weak self] in
            self?.currentPlaybackSnapshot.currentTrack?.artworkURL
        },
    )
    lazy var lifecycleCoordinator = NowPlayingApplicationLifecycleCoordinator { [weak self] suspended in
        self?.setInterfaceSuspended(suspended)
    }

    lazy var queueShuffleFeedbackCoordinator = NowPlayingQueueShuffleFeedbackCoordinator { [weak self] isActive in
        self?.pageViewController.setQueueShuffleFeedbackActive(isActive)
    }

    lazy var pageViewController = NowPlayingCompactPageController(environment: environment)
    let controlIslandViewModel = NowPlayingControlIslandViewModel()
    let routePickerPresenter = NowPlayingRoutePickerPresenter()
    lazy var playlistMenuProvider = AddToPlaylistMenuProvider(
        playlistStore: environment.playlistStore,
        viewController: self,
    )
    lazy var lyricsReloadPresenter = LyricsReloadPresenter(
        reloadService: environment.lyricsReloadService,
        viewController: self,
    )
    lazy var songContextMenuProvider = SongContextMenuProvider(
        playlistMenuProvider: playlistMenuProvider,
        lyricsReloadPresenter: lyricsReloadPresenter,
    )
    var cancellables: Set<AnyCancellable> = []
    var lastPresentedTrackID: String?
    var lastPresentedArtworkURL: URL?
    var currentPlaybackSnapshot = PlaybackSnapshot.empty
    private(set) var isInterfaceSuspended = false
    private var isNowPlayingSurfaceVisible = false
    private var isHoldingLyricsScreenAwake = false

    init(environment: AppEnvironment) {
        self.environment = environment
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    private let grabHandle: UIView = {
        let handle = UIView()
        handle.backgroundColor = UIColor.white.withAlphaComponent(0.4)
        handle.layer.cornerCurve = .continuous
        handle.layer.cornerRadius = 2.5
        handle.isUserInteractionEnabled = false
        return handle
    }()

    /// Takes drags that start around the handle, so they close Now Playing.
    /// Without it they land on the lyric or queue list, which
    /// LNPopupController scrolls instead of closing unless the list is at its
    /// top.
    private let grabHandleDragRegion = UIView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        installBackgroundView()
        installPageViewController()
        installGrabHandle()
        bindQueueSectionActions()
        bindContentSelector()
        bindQueueSnapshot()
        lifecycleCoordinator.bind()
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
        isNowPlayingSurfaceVisible = true
        refreshLyricsScreenAwakeHold()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        isNowPlayingSurfaceVisible = false
        refreshLyricsScreenAwakeHold()
    }

    func refreshLyricsScreenAwakeHold() {
        updateLyricsScreenAwakeHold(
            shouldHold: isNowPlayingSurfaceVisible
                && controlIslandViewModel.selectedContentSelector == .lyrics,
            isHoldingScreenAwake: &isHoldingLyricsScreenAwake,
        )
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

    func installQueueActionHandlers(
        onToggleShuffle: @escaping () -> Void,
        onSelectQueueTrack: @escaping (NowPlayingQueueTrackSelection) -> Void,
        onRemoveQueueTrack: @escaping (Int) -> Void,
        onRestartCurrentTrack: @escaping () -> Void,
        onPlayFromHere: @escaping (Int) -> Void,
        onPlayNext: @escaping (Int) -> Void,
        onCycleRepeatMode: @escaping () -> Void,
    ) {
        configureQueueActionPresenter(
            pageViewController,
            onToggleShuffle: { [weak self] in
                guard self != nil else { return }
                onToggleShuffle()
            },
            onSelectQueueTrack: onSelectQueueTrack,
            onRemoveQueueTrack: onRemoveQueueTrack,
            onRestartCurrentTrack: onRestartCurrentTrack,
            onPlayFromHere: onPlayFromHere,
            onPlayNext: onPlayNext,
            onCycleRepeatMode: onCycleRepeatMode,
        )
    }

    func setInterfaceSuspended(_ suspended: Bool) {
        updateInterfaceSuspensionState(suspended, isInterfaceSuspended: &isInterfaceSuspended)
    }

    func setInterfacePresentationSuspended(_ suspended: Bool) {
        pageViewController.setInterfaceSuspended(suspended)
    }

    private func installGrabHandle() {
        view.addSubview(grabHandleDragRegion)
        view.addSubview(grabHandle)
        grabHandle.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top).offset(8)
            make.width.equalTo(64)
            make.height.equalTo(5)
        }
        grabHandleDragRegion.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.bottom.equalTo(grabHandle.snp.bottom).offset(16)
        }
    }

    private func installPageViewController() {
        bindArtworkSectionActions(pageViewController)
        pageViewController.onPageChanged = { [weak self] selector in
            self?.controlIslandViewModel.setContentSelector(selector)
        }
        pageViewController.onLyricTapped = { [weak self] in
            self?.controlIslandViewModel.setContentSelector(.lyrics)
        }

        addChild(pageViewController)
        view.addSubview(pageViewController.view)
        pageViewController.view.accessibilityIdentifier = "nowplaying.pages"
        pageViewController.view.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        pageViewController.didMove(toParent: self)
    }

    func prepareForPopupOpen() {
        prepareForPopupPresentation {
            updatePopupCloseButtonAppearance(for: controlIslandViewModel.selectedContentSelector)
            pageViewController.ensureCurrentPageIsLaidOut()
        }
    }

    func updatePopupCloseButtonAppearance(for _: NowPlayingControlIslandViewModel.ContentSelector) {
        hidePopupCloseButton()
    }
}
