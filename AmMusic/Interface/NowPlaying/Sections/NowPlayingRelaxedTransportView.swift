//
//  NowPlayingRelaxedTransportView.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import SnapKit
import Then
import UIKit

final class NowPlayingRelaxedTransportView: NowPlayingTransportView {
    let segmentedControl = UISegmentedControl(
        items: [
            String(localized: "Lyrics"),
            String(localized: "Queue"),
        ],
    ).then {
        $0.selectedSegmentIndex = 0
        let clearImage = UIImage()
        $0.setBackgroundImage(clearImage, for: .normal, barMetrics: .default)
        $0.setBackgroundImage(clearImage, for: .selected, barMetrics: .default)
        $0.setBackgroundImage(clearImage, for: .highlighted, barMetrics: .default)
        $0.setDividerImage(clearImage, forLeftSegmentState: .normal, rightSegmentState: .normal, barMetrics: .default)
        $0.setDividerImage(clearImage, forLeftSegmentState: .selected, rightSegmentState: .normal, barMetrics: .default)
        $0.setDividerImage(clearImage, forLeftSegmentState: .normal, rightSegmentState: .selected, barMetrics: .default)
        $0.backgroundColor = .clear
        $0.setTitleTextAttributes([
            .foregroundColor: UIColor.white.withAlphaComponent(0.4),
            .font: UIFont.systemFont(ofSize: 13, weight: .medium),
        ], for: .normal)
        $0.setTitleTextAttributes([
            .foregroundColor: UIColor.white,
            .font: UIFont.systemFont(ofSize: 13, weight: .semibold),
        ], for: .selected)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        let container = UIView()
        container.addSubview(segmentedControl)
        segmentedControl.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.equalTo(180)
            make.height.equalTo(32)
            make.top.bottom.equalToSuperview()
        }
        installSupplementaryView(container)
    }
}
