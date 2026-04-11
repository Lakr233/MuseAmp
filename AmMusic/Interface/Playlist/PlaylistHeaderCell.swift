//
//  PlaylistHeaderCell.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import SnapKit
import Then
import UIKit

final class PlaylistHeaderCell: TableBaseCell {
    static let reuseID = "PlaylistHeaderCell"

    let artworkImageView = AmImageView()

    private let shadowContainer = UIView().then {
        $0.layer.shadowColor = UIColor.black.cgColor
        $0.layer.shadowOpacity = 0.25
        $0.layer.shadowRadius = 10
        $0.layer.shadowOffset = CGSize(width: 0, height: 5)
    }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        artworkImageView.configure(placeholder: "music.note.list", cornerRadius: 12)

        shadowContainer.addSubview(artworkImageView)
        artworkImageView.snp.makeConstraints { $0.edges.equalToSuperview() }

        contentView.addSubview(shadowContainer)

        shadowContainer.snp.makeConstraints { make in
            make.size.equalTo(200).priority(.high)
            make.top.equalToSuperview().offset(InterfaceStyle.Spacing.medium).priority(.high)
            make.centerX.equalToSuperview()
            make.bottom.equalToSuperview().inset(InterfaceStyle.Spacing.medium).priority(.high)
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        artworkImageView.reset()
    }
}
