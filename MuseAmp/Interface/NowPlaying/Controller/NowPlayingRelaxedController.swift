//
//  NowPlayingRelaxedController.swift
//  MuseAmp
//
//  Created by @Lakr233 on 2026/04/11.
//

import Combine
import LNPopupController
import MuseAmpPlayerKit
import SnapKit
import UIKit

class NowPlayingRelaxedController: UIViewController, NowPlayingQueueShellController, NowPlayingArtworkShellController, NowPlayingLifecycleShellController {
    let environment: AppEnvironment
    let backgroundView = NowPlayingArtworkBackgroundView()
    lazy var artworkBackgroundCoordinator = NowPlayingArtworkBackgroundCoordinator(
        backgroundView: backgroundView,
        logOwner: "NowPlayingRelaxedController",
        currentArtworkURL: { [weak self] in
            self?.currentPlaybackSnapshot.currentTrack?.artworkURL
        },
    )
    lazy var lifecycleCoordinator = NowPlayingApplicationLifecycleCoordinator { [weak self] suspended in
        self?.setInterfaceSuspended(suspended)
    }

    lazy var queueShuffleFeedbackCoordinator = NowPlayingQueueShuffleFeedbackCoordinator { [weak self] isActive in
        self?.listSectionView.setShuffleFeedbackActive(isActive)
    }

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

    // MARK: - Section Views

    lazy var relaxedTransportView = NowPlayingRelaxedTransportView(environment: environment)
    lazy var centerSectionView = NowPlayingCenterSectionView(environment: environment, transportContentView: relaxedTransportView)
    lazy var lyricTimelineView = LyricTimelineView(environment: environment)
    let listSectionView = NowPlayingListSectionView()
    private let queuePanelView: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        return view
    }()

    lazy var relaxedShellView = NowPlayingRelaxedShellView(
        leftContentView: centerSectionView,
        lyricsPanelView: lyricTimelineView,
        queuePanelView: queuePanelView,
    )

    // MARK: - Right Panel

    private(set) var currentRightPanel: NowPlayingRelaxedPanel = .lyrics

    // MARK: - State

    var cancellables: Set<AnyCancellable> = []
    var lastPresentedTrackID: String?
    var lastPresentedArtworkURL: URL?
    var currentPlaybackSnapshot = PlaybackSnapshot.empty
    private(set) var isInterfaceSuspended = false
    private var isNowPlayingSurfaceVisible = false
    private var isHoldingLyricsScreenAwake = false

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
        hideTitlebarScrollEdgeEffects()
        bindQueueSectionActions()
        bindContentSelector()
        bindQueueSnapshot()
        lifecycleCoordinator.bind()
        bindCleanSongTitlePreference()
        applyInitialPlaybackPresentation()
        bindPlaybackSnapshot()
        bindPlaybackTime()
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

    private func refreshLyricsScreenAwakeHold() {
        updateLyricsScreenAwakeHold(
            shouldHold: isNowPlayingSurfaceVisible && currentRightPanel == .lyrics,
            isHoldingScreenAwake: &isHoldingLyricsScreenAwake,
        )
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
            listSectionView,
            onToggleShuffle: onToggleShuffle,
            onSelectQueueTrack: onSelectQueueTrack,
            onRemoveQueueTrack: onRemoveQueueTrack,
            onRestartCurrentTrack: onRestartCurrentTrack,
            onPlayFromHere: onPlayFromHere,
            onPlayNext: onPlayNext,
            onCycleRepeatMode: onCycleRepeatMode,
        )
    }

    // MARK: - Content Layout

    private func installContentLayout() {
        view.addSubview(relaxedShellView)
        relaxedShellView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    private func installLeftPanel() {
        bindArtworkSectionActions(self)

        relaxedTransportView.segmentedControl.addTarget(
            self,
            action: #selector(segmentedControlChanged(_:)),
            for: .valueChanged,
        )
    }

    private func installRightPanel() {
        queuePanelView.addSubview(listSectionView)
        listSectionView.snp.makeConstraints { make in
            make.top.bottom.equalToSuperview()
            make.leading.trailing.equalToSuperview().inset(16)
        }
    }

    /// On Mac every scroll view that reaches the top of the window gets a
    /// hard edge effect under the hidden title bar. Now Playing has no bar
    /// there, so the effect only draws an empty tinted strip with a divider
    /// over the artwork and lyric columns.
    private func hideTitlebarScrollEdgeEffects() {
        #if targetEnvironment(macCatalyst)
            guard #available(iOS 26.0, *) else { return }
            let scrollViews: [UIScrollView] = [
                centerSectionView.scrollView,
                lyricTimelineView.tableView,
                listSectionView.queueTableView,
            ]
            for scrollView in scrollViews {
                scrollView.topEdgeEffect.isHidden = true
            }
        #endif
    }

    @objc private func segmentedControlChanged(_ sender: UISegmentedControl) {
        let panel: NowPlayingRelaxedPanel = sender.selectedSegmentIndex == 0 ? .lyrics : .queue
        switchRightPanel(to: panel, animated: true)

        let selector: NowPlayingControlIslandViewModel.ContentSelector = panel == .lyrics ? .lyrics : .queue
        controlIslandViewModel.setContentSelector(selector)
    }

    // MARK: - Right Panel Toggle

    func switchRightPanel(to panel: NowPlayingRelaxedPanel, animated: Bool) {
        guard panel != currentRightPanel else { return }
        currentRightPanel = panel
        refreshLyricsScreenAwakeHold()

        switch panel {
        case .lyrics:
            relaxedTransportView.segmentedControl.selectedSegmentIndex = 0
        case .queue:
            relaxedTransportView.segmentedControl.selectedSegmentIndex = 1
        }

        relaxedShellView.switchRightPanel(to: panel, animated: animated)
    }

    // MARK: - Popup

    func prepareForPopupOpen() {
        prepareForPopupPresentation {
            hidePopupCloseButton()
        }
    }

    // MARK: - Application Lifecycle

    func setInterfaceSuspended(_ suspended: Bool) {
        updateInterfaceSuspensionState(suspended, isInterfaceSuspended: &isInterfaceSuspended)
    }

    func setInterfacePresentationSuspended(_ suspended: Bool) {
        relaxedTransportView.setAnimationsSuspended(suspended)
    }
}
