//
//  NowPlayingCompactTransportView.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import GlyphixTextFx
import Then
import UIKit

final class NowPlayingCompactTransportView: NowPlayingTransportView {
    private let currentLyricLabel = GlyphixTextLabel().then {
        $0.font = UIFontMetrics(forTextStyle: .footnote).scaledFont(
            for: .systemFont(ofSize: 13, weight: .medium),
        )
        $0.textColor = .white
        $0.textAlignment = .center
        $0.numberOfLines = 1
        $0.lineBreakMode = .byTruncatingTail
        $0.isBlurEffectEnabled = false
        $0.isSmoothRenderingEnabled = false
        $0.countsDown = true
        $0.clipsToBounds = false
        $0.isHidden = true
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        installSupplementaryView(currentLyricLabel)
    }

    override func setAnimationsSuspended(_ suspended: Bool) {
        super.setAnimationsSuspended(suspended)
        currentLyricLabel.disablesAnimations = suspended
    }

    func updateCurrentLyricLine(_ line: String?) {
        let hasLine = line != nil && !line!.isEmpty
        currentLyricLabel.text = line
        currentLyricLabel.isHidden = !hasLine
        Interface.smoothSpringAnimate {
            self.layoutAnimationContainerView().layoutIfNeeded()
        }
    }

    private func layoutAnimationContainerView() -> UIView {
        var responder: UIResponder? = self
        while let currentResponder = responder {
            if let viewController = currentResponder as? UIViewController {
                return viewController.view
            }
            responder = currentResponder.next
        }
        return self
    }
}
