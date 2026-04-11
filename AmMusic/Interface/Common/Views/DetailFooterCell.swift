//
//  DetailFooterCell.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import SnapKit
import Then
import UIKit

final class DetailFooterCell: TableBaseCell {
    static let reuseID = "DetailFooterCell"

    private let listEndDecorationView = ListEndDecorationView()

    private let infoLabel = UILabel().then {
        $0.font = .preferredFont(forTextStyle: .footnote)
        $0.textColor = .secondaryLabel
        $0.numberOfLines = 0
    }

    private let badgeStack = UIStackView().then {
        $0.axis = .horizontal
        $0.spacing = 6
        $0.alignment = .center
        $0.isHidden = true
    }

    private let losslessBadge = makeAlbumBadgeView(text: String(localized: "Lossless"), icon: "waveform")
    private let atmosBadge = makeAlbumBadgeView(text: String(localized: "Dolby Atmos"), icon: "hifispeaker.2.fill")
    private let spatialBadge = makeAlbumBadgeView(text: String(localized: "Spatial"), icon: "ear.fill")

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        badgeStack.addArrangedSubview(losslessBadge)
        badgeStack.addArrangedSubview(atmosBadge)
        badgeStack.addArrangedSubview(spatialBadge)
        losslessBadge.isHidden = true
        atmosBadge.isHidden = true
        spatialBadge.isHidden = true

        contentView.addSubview(listEndDecorationView)
        contentView.addSubview(infoLabel)
        contentView.addSubview(badgeStack)

        listEndDecorationView.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(InterfaceStyle.Spacing.small).priority(.high)
            make.centerX.equalToSuperview().priority(.high)
            make.leading.greaterThanOrEqualToSuperview().offset(56).priority(.high)
            make.trailing.lessThanOrEqualToSuperview().inset(56).priority(.high)
            make.width.lessThanOrEqualTo(256).priority(.high)
        }

        infoLabel.snp.makeConstraints { make in
            make.top.equalTo(listEndDecorationView.snp.bottom).offset(InterfaceStyle.Spacing.medium).priority(.high)
            make.leading.trailing.equalToSuperview().inset(20).priority(.high)
        }

        badgeStack.snp.makeConstraints { make in
            make.top.equalTo(infoLabel.snp.bottom).offset(InterfaceStyle.Spacing.small).priority(.high)
            make.leading.equalToSuperview().inset(20).priority(.high)
            make.bottom.equalToSuperview().inset(InterfaceStyle.Spacing.large).priority(.high)
        }
    }

    func configure(text: String?, audioTraits: [String] = []) {
        infoLabel.text = text
        configureBadges(audioTraits: audioTraits)
    }

    private func configureBadges(audioTraits traits: [String]) {
        let showLossless = traits.contains("lossless")
        let showAtmos = traits.contains("atmos")
        let showSpatial = traits.contains("spatial") && !traits.contains("atmos")
        let showAny = showLossless || showAtmos || showSpatial

        losslessBadge.isHidden = !showLossless
        atmosBadge.isHidden = !showAtmos
        spatialBadge.isHidden = !showSpatial
        badgeStack.isHidden = !showAny
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        infoLabel.text = nil
        losslessBadge.isHidden = true
        atmosBadge.isHidden = true
        spatialBadge.isHidden = true
        badgeStack.isHidden = true
    }
}
