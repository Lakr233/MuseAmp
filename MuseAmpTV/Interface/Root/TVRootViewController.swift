import Combine
import MuseAmpPlayerKit
import SnapKit
import UIKit

@MainActor
final class TVRootViewController: UIViewController {
    private let context: TVAppContext
    private let sessionStateAdapter: TVSessionStateAdapter
    private var cancellables: Set<AnyCancellable> = []

    private var state: AMTVRootFlowState {
        sessionStateAdapter.sessionState.rootFlowState
    }

    // MARK: - Subviews

    private let backgroundView = TVRootBackgroundView()
    private let qrPairingView = TVQRPairingView()
    private let transferProgressView = TVTransferProgressView()
    private let nowPlayingController: TVNowPlayingController

    private var hasPerformedSlideToProgress = false
    private var previousState: AMTVRootFlowState?

    init(context: TVAppContext) {
        self.context = context
        sessionStateAdapter = TVSessionStateAdapter(context: context)
        nowPlayingController = TVNowPlayingController(context: context)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupViewHierarchy()
        setupLayout()
        view.layoutIfNeeded()
        bindPlayback()
        bindActions()
        sessionStateAdapter.onStateChanged = { [weak self] in
            self?.reloadContent()
        }
        sessionStateAdapter.activate()
        reloadContent()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        presentPendingSessionAlertIfNeeded()
        resumePlaybackAfterBoot()
    }

    private var didResumePlaybackAfterBoot = false

    private func resumePlaybackAfterBoot() {
        guard !didResumePlaybackAfterBoot else { return }
        didResumePlaybackAfterBoot = true

        guard context.playbackController.latestSnapshot.state == .paused else { return }

        nowPlayingController.view.alpha = 0
        context.playbackController.togglePlayPause()
        Interface.animate(duration: 0.5) {
            self.nowPlayingController.view.alpha = 1
        }
    }

    // MARK: - State Reload

    func reloadContent() {
        sessionStateAdapter.syncReceiverAvailability()

        let currentState = state
        let needsCrossfade = previousState == .playing && currentState != .playing
        previousState = currentState

        let applyState = {
            switch currentState {
            case .awaitingUpload, .failed:
                self.qrPairingView.configure(content: self.sessionStateAdapter.uploadWaitingContent)
                self.qrPairingView.updateDiscoveredSenders(self.sessionStateAdapter.discoveredDevices)

                if self.hasPerformedSlideToProgress {
                    self.showPairing()
                } else {
                    self.qrPairingView.isHidden = false
                    self.qrPairingView.isUserInteractionEnabled = true
                    self.transferProgressView.isHidden = true
                }
                self.nowPlayingController.view.isHidden = true

            case .receivingTracks:
                if let content = self.sessionStateAdapter.receivingTracksContent {
                    self.transferProgressView.configure(content: content)
                }
                if !self.hasPerformedSlideToProgress {
                    self.showProgress()
                }
                self.nowPlayingController.view.isHidden = true

            case .playing:
                self.resetSlideState()
                self.qrPairingView.isHidden = true
                self.transferProgressView.isHidden = true
                self.nowPlayingController.view.isHidden = false
            }
        }

        if let snapshot = needsCrossfade ? view.snapshotView(afterScreenUpdates: false) : nil {
            view.addSubview(snapshot)
            snapshot.frame = view.bounds
            snapshot.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            applyState()
            Interface.animate(duration: 0.35, options: .curveEaseInOut) {
                snapshot.alpha = 0
            } completion: { _ in
                snapshot.removeFromSuperview()
                self.setNeedsFocusUpdate()
                self.updateFocusIfNeeded()
            }
        } else {
            applyState()
            setNeedsFocusUpdate()
            updateFocusIfNeeded()
        }

        if case let .failed(message) = sessionStateAdapter.sessionState {
            if sessionStateAdapter.isDisconnectedTransfer {
                presentTransferDisconnectedAlert(message: message)
            } else {
                presentFailureAlert(title: String(localized: "Transfer Failed"), message: message)
            }
        }

        if view.window != nil {
            presentPendingSessionAlertIfNeeded()
        }
    }

    // MARK: - State Transitions

    private func showProgress() {
        hasPerformedSlideToProgress = true
        qrPairingView.isHidden = true
        qrPairingView.isUserInteractionEnabled = false
        transferProgressView.isHidden = false
        transferProgressView.transform = .identity
        transferProgressView.alpha = 1
        setNeedsFocusUpdate()
        updateFocusIfNeeded()
    }

    private func slideToProgress(completion: @escaping () -> Void) {
        hasPerformedSlideToProgress = true
        qrPairingView.isUserInteractionEnabled = false

        transferProgressView.isHidden = false
        transferProgressView.transform = CGAffineTransform(translationX: view.bounds.width, y: 0)
        transferProgressView.alpha = 0

        Interface.smoothSpringAnimate {
            self.qrPairingView.transform = CGAffineTransform(translationX: -self.view.bounds.width * 0.3, y: 0)
            self.qrPairingView.alpha = 0
            self.transferProgressView.transform = .identity
            self.transferProgressView.alpha = 1
        } completion: { _ in
            self.qrPairingView.isHidden = true
            self.setNeedsFocusUpdate()
            self.updateFocusIfNeeded()
            completion()
        }
    }

    private func showPairing() {
        hasPerformedSlideToProgress = false
        qrPairingView.isHidden = false
        qrPairingView.isUserInteractionEnabled = true
        qrPairingView.transform = .identity
        qrPairingView.alpha = 1
        transferProgressView.isHidden = true
        setNeedsFocusUpdate()
        updateFocusIfNeeded()
    }

    private func resetSlideState() {
        hasPerformedSlideToProgress = false
        qrPairingView.transform = .identity
        qrPairingView.alpha = 1
        qrPairingView.isUserInteractionEnabled = true
        transferProgressView.transform = .identity
        transferProgressView.alpha = 1
    }

    // MARK: - Focus

    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        switch state {
        case .awaitingUpload, .failed:
            [qrPairingView]
        case .receivingTracks:
            [transferProgressView]
        case .playing:
            [nowPlayingController]
        }
    }

    // MARK: - View Setup

    private func setupViewHierarchy() {
        view.addSubview(backgroundView)
        view.addSubview(qrPairingView)
        view.addSubview(transferProgressView)

        addChild(nowPlayingController)
        view.addSubview(nowPlayingController.view)
        nowPlayingController.didMove(toParent: self)

        transferProgressView.isHidden = true
    }

    private func setupLayout() {
        backgroundView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        qrPairingView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.equalToSuperview().inset(32)
            make.height.lessThanOrEqualToSuperview()
        }
        transferProgressView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.equalToSuperview().inset(32)
            make.height.lessThanOrEqualToSuperview()
        }
        nowPlayingController.view.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    private var lastBackgroundTrackID: String?
    private var playbackWasActive = false

    private func bindPlayback() {
        context.playbackController.$snapshot
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in
                guard let self else { return }

                if snapshot.currentTrack != nil {
                    playbackWasActive = true
                }

                if playbackWasActive,
                   snapshot.currentTrack == nil,
                   snapshot.queue.isEmpty,
                   snapshot.state == .idle,
                   context.currentSessionManifest != nil
                {
                    playbackWasActive = false
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        let restarted = await context.playCurrentSession()
                        if !restarted {
                            await context.clearSessionLibrary()
                        }
                    }
                }

                reloadContent()
                let trackID = snapshot.currentTrack?.id
                guard trackID != lastBackgroundTrackID else { return }
                lastBackgroundTrackID = trackID
                backgroundView.updateForArtwork(url: snapshot.currentTrack?.artworkURL)
            }
            .store(in: &cancellables)
    }

    private func bindActions() {
        qrPairingView.onSenderSelected = { [weak self] device in
            self?.beginConnection(to: device)
        }
    }

    // MARK: - Connection

    private var connectingAlert: UIAlertController?

    private func beginConnection(to device: DiscoveredDevice) {
        let alert = UIAlertController(
            title: String(localized: "Connecting…"),
            message: String(localized: "Authenticating with \(device.deviceName)"),
            preferredStyle: .alert,
        )
        connectingAlert = alert
        present(alert, animated: true)

        sessionStateAdapter.onConnectResult = { [weak self] success, errorMessage in
            guard let self, let presented = connectingAlert else { return }
            connectingAlert = nil
            presented.dismiss(animated: true) {
                guard success else {
                    self.presentFailureAlert(
                        title: String(localized: "Authentication Failed"),
                        message: errorMessage ?? String(localized: "Authentication failed."),
                    )
                    return
                }
                self.slideToProgress {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        self.sessionStateAdapter.proceedWithTransfer()
                    }
                }
            }
        }

        sessionStateAdapter.connect(to: device, password: context.pairingCode)
    }

    // MARK: - Alerts

    private func presentFailureAlert(title: String, message: String) {
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(
            title: title,
            message: message,
            preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default) { [weak self] _ in
            self?.sessionStateAdapter.refreshDiscovery()
        })
        present(alert, animated: true)
    }

    private func presentTransferDisconnectedAlert(message: String) {
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(
            title: String(localized: "Transfer Interrupted"),
            message: message,
            preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(title: String(localized: "Retry"), style: .default) { [weak self] _ in
            self?.sessionStateAdapter.retryTransfer()
        })
        alert.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel) { [weak self] _ in
            self?.sessionStateAdapter.refreshDiscovery()
        })
        present(alert, animated: true)
    }

    private func presentCancelTransferConfirmation() {
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(
            title: String(localized: "Cancel Transfer?"),
            message: String(localized: "This will stop the current transfer and return to the pairing screen."),
            preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(title: String(localized: "Continue Transfer"), style: .cancel))
        alert.addAction(
            UIAlertAction(
                title: String(localized: "Cancel Transfer"),
                style: .destructive,
                handler: { [weak self] _ in
                    self?.sessionStateAdapter.cancelTransfer()
                },
            ),
        )
        present(alert, animated: true)
    }

    private func presentStatusAlert(title: String, message: String) {
        let alert = UIAlertController(
            title: title,
            message: message,
            preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
        present(alert, animated: true)
    }

    private func presentPendingSessionAlertIfNeeded() {
        guard let alert = context.takePendingSessionAlert()
        else {
            return
        }

        presentStatusAlert(
            title: alert.title,
            message: alert.message,
        )
    }

    private func presentLeaveSessionConfirmation() {
        guard presentedViewController == nil else {
            return
        }

        let alert = UIAlertController(
            title: String(localized: "Leave Playlist Session"),
            message: String(localized: "Leaving deletes the transferred playlist from this Apple TV and returns to the receive screen."),
            preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel))
        alert.addAction(
            UIAlertAction(
                title: String(localized: "Delete Playlist"),
                style: .destructive,
                handler: { [weak self] _ in
                    self?.sessionStateAdapter.resetSession()
                },
            ),
        )
        present(alert, animated: true)
    }

    // MARK: - Menu Button

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let isMenuPress = presses.contains { $0.type == .menu }
        guard isMenuPress, presentedViewController == nil else {
            super.pressesBegan(presses, with: event)
            return
        }

        let currentState = state
        if currentState == .playing {
            presentLeaveSessionConfirmation()
            return
        }
        if currentState == .receivingTracks {
            presentCancelTransferConfirmation()
            return
        }

        super.pressesBegan(presses, with: event)
    }
}
