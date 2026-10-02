import LNPopupController
import MuseAmpPlayerKit
import SnapKit
import UIKit

@MainActor
protocol NowPlayingLifecycleShellController: NowPlayingPlaybackShellController {
    var backgroundView: NowPlayingArtworkBackgroundView { get }
    var queueShuffleFeedbackCoordinator: NowPlayingQueueShuffleFeedbackCoordinator { get }

    func setInterfacePresentationSuspended(_ suspended: Bool)
}

extension NowPlayingLifecycleShellController where Self: UIViewController {
    func installBackgroundView() {
        view.addSubview(backgroundView)
        backgroundView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        artworkBackgroundCoordinator.applyIdleBackground()
    }

    func hidePopupCloseButton() {
        let popupContentView = popupPresentationContainer?.popupContentView
        popupContentView?.popupCloseButtonStyle = .none
        popupContentView?.popupCloseButton.isHidden = true
    }

    func updateInterfaceSuspensionState(
        _ suspended: Bool,
        isInterfaceSuspended: inout Bool,
    ) {
        guard isInterfaceSuspended != suspended else { return }

        isInterfaceSuspended = suspended
        setInterfacePresentationSuspended(suspended)
        backgroundView.setAnimationSuspended(suspended)

        if suspended {
            artworkBackgroundCoordinator.cancel()
            queueShuffleFeedbackCoordinator.cancel()
            return
        }

        refreshControlIslandContent()
        refreshPlayingContent(animated: false)
    }

    func updateLyricsScreenAwakeHold(
        shouldHold: Bool,
        isHoldingScreenAwake: inout Bool,
    ) {
        guard shouldHold != isHoldingScreenAwake else { return }
        isHoldingScreenAwake = shouldHold
        environment.screenAwakeCoordinator.setActive(shouldHold, for: .lyricsVisible)
    }

    func prepareForPopupPresentation(additionalUpdates: () -> Void = {}) {
        AppLog.info(self, "prepareForPopupOpen isPlaying=\(currentPlaybackSnapshot.state == .playing)")
        loadViewIfNeeded()
        refreshPlayingContent(animated: false)

        let presentation = controlIslandViewModel.apply(snapshot: currentPlaybackSnapshot)
        artworkBackgroundCoordinator.update(
            using: presentation.backgroundSource,
            animated: false,
        )

        additionalUpdates()
    }
}
