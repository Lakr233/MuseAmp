//
//  NowPlayingQueueFooterCell.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import SnapKit
import Then
import UIKit

final class NowPlayingQueueFooterCell: TableBaseCell {
    static let reuseID = "NowPlayingQueueFooterCell"

    private let summaryLabel = UILabel().then {
        $0.textColor = UIColor.white.withAlphaComponent(0.48)
        $0.font = UIFontMetrics(forTextStyle: .footnote).scaledFont(
            for: .systemFont(ofSize: 13, weight: .regular),
        )
        $0.adjustsFontForContentSizeCategory = true
        $0.textAlignment = .center
        $0.numberOfLines = 0
    }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        selectionStyle = .none

        contentView.addSubview(summaryLabel)
        summaryLabel.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: 12, left: 20, bottom: 12, right: 20))
        }
    }

    func configure(remainingCount: Int, totalMinutes: Int) {
        let totalText = String(localized: "Queue Footer Total Minutes \(totalMinutes)")
        if remainingCount > 0 {
            let remainingText = String(localized: "Queue Footer Remaining \(remainingCount)")
            summaryLabel.text = remainingText + " " + totalText
        } else {
            summaryLabel.text = totalText
        }
    }
}
