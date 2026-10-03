import Combine
import UIKit

final class PreviousPlayerControlButton: PlayerControlButton {
    override init(playbackController: PlaybackController) {
        super.init(playbackController: playbackController)
        var configuration = UIButton.Configuration.plain()
        configuration.baseForegroundColor = .white
        configuration.contentInsets = .zero
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
            pointSize: 20,
            weight: .regular,
        )
        self.configuration = configuration
        tintColor = .white
        setImage(UIImage(systemName: "backward.fill"), for: .normal)
        accessibilityLabel = String(localized: "Previous")
    }

    override func didTap() {
        super.didTap()
        playbackController.previous()
    }

    override func bindState() {
        // Previous restarts the track once it passes 3 s, so the button also
        // follows time ticks, which do not republish the snapshot.
        let timeUpdates = playbackController.playbackTimeSubject
            .map { [playbackController] time in
                playbackController.latestSnapshot.withTime(time.currentTime, duration: time.duration)
            }
        playbackController.$snapshot
            .merge(with: timeUpdates)
            .map { $0.currentTrack != nil && NowPlayingContentMapper.isPreviousAvailable(for: $0) }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isEnabled in
                self?.isEnabled = isEnabled
                self?.alpha = isEnabled ? 1 : 0.1
            }
            .store(in: &controlCancellables)
    }
}
