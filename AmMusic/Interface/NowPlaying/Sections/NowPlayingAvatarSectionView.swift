//
//  NowPlayingAvatarSectionView.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import SnapKit
import Then
import UIKit

final class NowPlayingAvatarSectionView: UIView {
    private let artworkView = NowPlayingArtworkImageView().then {
        $0.configure(placeholder: "music.note", cornerRadius: NowPlayingArtworkLayout.artworkCornerRadius)
    }

    private var displayedArtworkURL: URL?

    var onArtworkLoaded: (URL, UIImage) -> Void = { _, _ in } {
        didSet {
            artworkView.onImageLoaded = onArtworkLoaded
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(artworkView)

        artworkView.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(NowPlayingArtworkLayout.artworkInset).priority(.high)
            make.width.equalTo(artworkView.snp.height)
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    func updateArtwork(url: URL?) {
        let previousURL = displayedArtworkURL
        displayedArtworkURL = url

        if previousURL == url {
            AppLog.verbose(
                self,
                "avatar refresh skipped artwork=\(nowPlayingLogURLDescription(url))",
            )
            return
        }

        AppLog.info(
            self,
            "avatar refresh requested previous=\(nowPlayingLogURLDescription(previousURL)) next=\(nowPlayingLogURLDescription(url))",
        )

        let shouldCrossfade = previousURL != nil && url != nil
        if shouldCrossfade {
            artworkView.crossfadeToImage(url: url)
        } else if let url {
            artworkView.loadImage(url: url)
        } else {
            artworkView.reset()
        }
    }
}

private final class NowPlayingArtworkImageView: AmImageView {
    private static let crossfadeDuration: TimeInterval = 0.35

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
