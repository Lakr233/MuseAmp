//
//  TVMusicProgressView.swift
//  MuseAmpTV
//
//  Playback progress bar with elapsed / remaining time labels.
//

import SnapKit
import SwifterSwift
import Then
import UIKit

@MainActor
final class TVMusicProgressView: UIView {
    private let elapsedLabel = UILabel().then {
        $0.font = roundedMonospacedDigitFont()
        $0.textColor = UIColor.white.withAlphaComponent(0.5)
        $0.textAlignment = .right
        $0.text = "0:00"
    }

    private let remainingLabel = UILabel().then {
        $0.font = roundedMonospacedDigitFont()
        $0.textColor = UIColor.white.withAlphaComponent(0.5)
        $0.textAlignment = .left
        $0.text = "-0:00"
    }

    private let trackView = UIView().then {
        $0.backgroundColor = UIColor.white.withAlphaComponent(0.2)
        $0.clipsToBounds = true
        $0.layer.cornerCurve = .continuous
        $0.layer.cornerRadius = TVNowPlayingLayout.progressCornerRadius
    }

    private let fillView = UIView().then {
        $0.backgroundColor = .white
        $0.clipsToBounds = true
        $0.layer.cornerCurve = .continuous
        $0.layer.cornerRadius = TVNowPlayingLayout.progressCornerRadius
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        trackView.addSubview(fillView)
        addSubviews([
            elapsedLabel,
            trackView,
            remainingLabel,
        ])

        elapsedLabel.snp.makeConstraints { make in
            make.width.equalTo(80)
            make.left.equalToSuperview()
            make.centerY.equalToSuperview().priority(.high)
            make.top.greaterThanOrEqualToSuperview()
            make.bottom.lessThanOrEqualToSuperview()
            make.height.lessThanOrEqualToSuperview()
        }
        remainingLabel.snp.makeConstraints { make in
            make.width.equalTo(80)
            make.right.equalToSuperview()
            make.centerY.equalToSuperview().priority(.high)
            make.top.greaterThanOrEqualToSuperview()
            make.bottom.lessThanOrEqualToSuperview()
            make.height.lessThanOrEqualToSuperview()
        }

        trackView.snp.makeConstraints { make in
            make.height.equalTo(TVNowPlayingLayout.progressHeight)
            make.height.lessThanOrEqualToSuperview()
            make.left.equalTo(elapsedLabel.snp.right).offset(32)
            make.right.equalTo(remainingLabel.snp.left).offset(-32)
            make.centerY.equalToSuperview().priority(.high)
        }
        fillView.snp.makeConstraints { make in
            make.leading.top.bottom.equalToSuperview()
            make.width.equalTo(0)
        }
    }

    @available(*, unavailable)
    required init(coder _: NSCoder) {
        fatalError()
    }

    func update(currentTime: TimeInterval, duration: TimeInterval, animated: Bool = false) {
        elapsedLabel.text = formattedPlaybackTime(currentTime)
        let remaining = max(duration - currentTime, 0)
        remainingLabel.text = "-\(formattedPlaybackTime(remaining))"

        let progress = duration > 0 ? CGFloat(currentTime / duration) : 0
        let clamped = min(max(progress, 0), 1)
        let fillWidth = trackView.bounds.width * clamped
        fillView.snp.updateConstraints { make in
            make.width.equalTo(fillWidth)
        }
        if animated {
            Interface.animate(duration: 0.2) {
                self.layoutIfNeeded()
            }
        }
    }

    private static func roundedMonospacedDigitFont() -> UIFont {
        let base = UIFont.monospacedDigitSystemFont(
            ofSize: TVNowPlayingLayout.bodyFontSize,
            weight: .semibold,
        )
        if let rounded = base.fontDescriptor.withDesign(.rounded) {
            return UIFont(descriptor: rounded, size: TVNowPlayingLayout.bodyFontSize)
        }
        return base
    }
}
