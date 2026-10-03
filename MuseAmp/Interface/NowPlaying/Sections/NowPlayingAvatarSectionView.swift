import Combine
import SnapKit
import UIKit

@MainActor
class NowPlayingAvatarSectionView: UIView {
    private let artworkView: NowPlayingArtworkImageView

    var onArtworkLoaded: (URL, UIImage) -> Void = { _, _ in } {
        didSet {
            artworkView.onImageLoaded = onArtworkLoaded
        }
    }

    init(environment: AppEnvironment) {
        artworkView = NowPlayingArtworkImageView(environment: environment)
        super.init(frame: UIScreen.main.bounds)

        artworkView.configure(
            placeholder: "music.note",
            cornerRadius: NowPlayingArtworkLayout.artworkCornerRadius,
        )

        addSubview(artworkView)
        artworkView.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(NowPlayingArtworkLayout.artworkInset)
            make.width.equalTo(artworkView.snp.height)
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }
}

private final class NowPlayingArtworkImageView: MuseAmpImageView {
    private static let crossfadeDuration: TimeInterval = 0.35
    private var cancellables = Set<AnyCancellable>()

    init(environment: AppEnvironment) {
        super.init(frame: UIScreen.main.bounds)
        environment.playbackController.$snapshot
            .map { $0.currentTrack?.artworkURL }
            .removeDuplicates { $0 == $1 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] url in
                self?.updateArtwork(url: url)
            }
            .store(in: &cancellables)
    }

    private func updateArtwork(url: URL?) {
        let previousURL = currentURL

        guard previousURL != url else {
            return
        }

        let shouldCrossfade = previousURL != nil && url != nil
        if shouldCrossfade {
            crossfadeToImage(url: url)
        } else if let url {
            loadImage(url: url)
        } else {
            reset()
        }
    }

    func crossfadeToImage(url: URL?) {
        guard let snapshot = snapshotView(afterScreenUpdates: false) else {
            loadImage(url: url)
            return
        }

        addSubview(snapshot)
        snapshot.frame = bounds
        snapshot.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        if let url {
            loadImage(url: url)
        } else {
            reset()
        }

        Interface.animate(
            duration: Self.crossfadeDuration,
            options: .curveEaseInOut,
        ) {
            snapshot.alpha = 0
        } completion: { _ in
            snapshot.removeFromSuperview()
        }
    }
}
