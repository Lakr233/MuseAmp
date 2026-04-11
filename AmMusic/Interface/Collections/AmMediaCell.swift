//
//  AmMediaCell.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import SnapKit
import Then
import UIKit

class AmMediaCell: TableBaseCell {
    static let reuseID = "AmMediaCell"

    private let mediaRowView = AmMediaRowView()
    private let disclosureImageView = UIImageView().then {
        $0.image = UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(
            pointSize: 13, weight: .semibold,
        ))
        $0.tintColor = .tertiaryLabel
        $0.contentMode = .scaleAspectFit
        $0.setContentHuggingPriority(.required, for: .horizontal)
        $0.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        contentView.addSubview(mediaRowView)
        contentView.addSubview(disclosureImageView)

        mediaRowView.snp.makeConstraints {
            $0.top.bottom.leading.equalToSuperview().inset(
                InterfaceStyle.Insets.symmetric(
                    vertical: InterfaceStyle.Spacing.xSmall,
                    horizontal: InterfaceStyle.Spacing.small,
                ),
            )
            $0.trailing.equalTo(disclosureImageView.snp.leading).offset(-8)
        }
        disclosureImageView.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.trailing.equalToSuperview().inset(InterfaceStyle.Spacing.small)
            make.width.equalTo(10)
        }
    }

    func configure(title: String, subtitle: String?, placeholderIcon: String, roundArtwork: Bool) {
        mediaRowView.configure(
            title: title,
            subtitle: subtitle,
            placeholderIcon: placeholderIcon,
            roundArtwork: roundArtwork,
        )
    }

    func configure(title: String, subtitle: String?, artworkURL: URL?, placeholderIcon: String, roundArtwork: Bool) {
        configure(
            title: title,
            subtitle: subtitle,
            placeholderIcon: placeholderIcon,
            roundArtwork: roundArtwork,
        )
        mediaRowView.loadArtwork(url: artworkURL)
    }

    func setAttributedTitle(_ attributedTitle: NSAttributedString) {
        mediaRowView.setAttributedTitle(attributedTitle)
    }

    func setAttributedSubtitle(_ attributedSubtitle: NSAttributedString?) {
        mediaRowView.setAttributedSubtitle(attributedSubtitle)
    }

    func setArtworkImage(_ image: UIImage) {
        mediaRowView.setArtworkImage(image)
    }

    func resetArtwork() {
        mediaRowView.resetArtwork()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        mediaRowView.prepareForReuse()
    }
}
