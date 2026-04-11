//
//  NowPlayingQueueEmptyCell.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import SnapKit
import Then
import UIKit

final class NowPlayingQueueEmptyCell: TableBaseCell {
    static let reuseID = "NowPlayingQueueEmptyCell"

    private let titleLabel = UILabel().then {
        $0.text = String(localized: "Queue is Empty")
        $0.textColor = UIColor.white.withAlphaComponent(0.72)
        $0.font = UIFontMetrics(forTextStyle: .body).scaledFont(
            for: .systemFont(ofSize: 16, weight: .medium),
        )
        $0.textAlignment = .center
        $0.numberOfLines = 0
    }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: 20, left: 16, bottom: 20, right: 16))
        }
    }
}
