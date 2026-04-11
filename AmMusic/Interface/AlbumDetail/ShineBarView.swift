//
//  ShineBarView.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import SnapKit
import Then
import UIKit

final class ShineBarView: UIView {
    private let gradientLayer = CAGradientLayer()
    private var lastBoundsSize: CGSize = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .tertiarySystemFill
        layer.cornerRadius = 4
        clipsToBounds = true

        gradientLayer.colors = [
            UIColor.clear.cgColor,
            UIColor.white.withAlphaComponent(0.3).cgColor,
            UIColor.clear.cgColor,
        ]
        gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        gradientLayer.locations = [0, 0.5, 1]
        layer.addSublayer(gradientLayer)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != lastBoundsSize, bounds.width > 0 else { return }
        lastBoundsSize = bounds.size
        gradientLayer.frame = CGRect(
            x: -bounds.width, y: 0, width: bounds.width * 3, height: bounds.height,
        )
        startShimmer()
    }

    private func startShimmer() {
        gradientLayer.removeAnimation(forKey: "shimmer")

        let animation = CABasicAnimation(keyPath: "transform.translation.x")
        animation.fromValue = -bounds.width * 2
        animation.toValue = bounds.width * 2
        animation.duration = 1.5
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        gradientLayer.add(animation, forKey: "shimmer")
    }
}

func makeAlbumBadgeView(text: String, icon: String) -> UIView {
    let imageView = UIImageView(image: UIImage(systemName: icon)).then {
        $0.tintColor = .tintColor
        $0.contentMode = .scaleAspectFit
        $0.snp.makeConstraints { make in make.size.equalTo(12) }
    }

    let label = UILabel().then {
        $0.text = text
        $0.font = .systemFont(ofSize: 11, weight: .semibold)
        $0.textColor = .tintColor
    }

    return UIStackView(arrangedSubviews: [imageView, label]).then {
        $0.axis = .horizontal
        $0.spacing = 3
        $0.alignment = .center
        $0.layoutMargins = UIEdgeInsets(top: 3, left: 8, bottom: 3, right: 8)
        $0.isLayoutMarginsRelativeArrangement = true
        $0.backgroundColor = UIColor.tintColor.withAlphaComponent(0.1)
        $0.layer.cornerRadius = 10
        $0.clipsToBounds = true
    }
}
