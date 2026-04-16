//
//  ArtistHeaderCell.swift
//  MuseAmp
//
//  Created by @libr on 2026/04/16.
//

import SnapKit
import UIKit

final class ArtistHeaderCell: TableBaseCell {
    static let reuseID = "ArtistHeaderCell"

    private let artworkImageView = MuseAmpImageView()
    private let nameLabel: CopyableLabel = {
        let label = CopyableLabel()
        label.font = .systemFont(ofSize: 21, weight: .bold)
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.textColor = PlatformInterfacePalette.secondaryText
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    private let shadowContainer: UIView = {
        let view = UIView()
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.25
        view.layer.shadowRadius = 8
        view.layer.shadowOffset = .zero
        return view
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        artworkImageView.configure(placeholder: "person.fill", cornerRadius: 18)
        artworkImageView.allowsPreviewOnTap = true

        let infoStack = UIStackView(arrangedSubviews: [nameLabel, subtitleLabel])
        infoStack.axis = .vertical
        infoStack.spacing = InterfaceStyle.Spacing.xSmall
        infoStack.alignment = .center

        shadowContainer.addSubview(artworkImageView)

        let contentStack = UIStackView(arrangedSubviews: [shadowContainer, infoStack])
        contentStack.axis = .vertical
        contentStack.spacing = InterfaceStyle.Spacing.medium
        contentStack.alignment = .center

        contentView.addSubview(contentStack)

        artworkImageView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        shadowContainer.snp.makeConstraints { make in
            make.size.equalTo(220)
        }
        contentStack.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(InterfaceStyle.Spacing.medium)
            make.leading.equalToSuperview().offset(InterfaceStyle.Spacing.medium)
            make.trailing.equalToSuperview().offset(-InterfaceStyle.Spacing.medium)
            make.bottom.equalToSuperview().offset(-InterfaceStyle.Spacing.small)
        }
    }

    func configure(name: String, subtitle: String?, artworkURL: URL?) {
        nameLabel.text = name
        subtitleLabel.text = subtitle
        subtitleLabel.isHidden = subtitle?.isEmpty != false
        artworkImageView.loadImage(url: artworkURL)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        nameLabel.text = nil
        subtitleLabel.text = nil
        subtitleLabel.isHidden = false
        artworkImageView.reset()
    }
}
