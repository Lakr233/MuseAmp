//
//  LibrarySearchResultCell.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import AmMusicDatabaseKit
import SnapKit
import Then
import UIKit

final class LibrarySearchResultCell: TableBaseCell {
    static let reuseID = "LibrarySearchResultCell"

    private let artworkView = AmImageView().then { $0.configure(placeholder: "music.note", cornerRadius: 6) }
    private let titleLabel = UILabel().then { $0.font = .systemFont(ofSize: 16); $0.textColor = .label }
    private let subtitleLabel = UILabel().then { $0.font = .systemFont(ofSize: 13); $0.textColor = .secondaryLabel }
    private let trailingLabel = UILabel().then {
        $0.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        $0.textColor = .tertiaryLabel
        $0.textAlignment = .right
        $0.setContentHuggingPriority(.required, for: .horizontal)
        $0.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    private let textStack = UIStackView()
    private let row = UIStackView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        clipsToBounds = true
        contentView.clipsToBounds = true

        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(subtitleLabel)
        textStack.do {
            $0.axis = .vertical
            $0.spacing = InterfaceStyle.Spacing.xSmall
        }

        row.addArrangedSubview(artworkView)
        row.addArrangedSubview(textStack)
        row.addArrangedSubview(trailingLabel)
        row.do {
            $0.axis = .horizontal
            $0.spacing = InterfaceStyle.Spacing.small
            $0.alignment = .center
        }

        contentView.addSubview(row)

        let insets = InterfaceStyle.Insets.symmetric(
            vertical: 6,
            horizontal: InterfaceStyle.Spacing.small,
        )
        artworkView.snp.makeConstraints { $0.size.equalTo(44) }
        row.snp.makeConstraints { $0.edges.equalToSuperview().inset(insets) }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        artworkView.reset()
        titleLabel.attributedText = nil
        subtitleLabel.attributedText = nil
        trailingLabel.text = nil
    }

    func configure(with track: AudioTrackRecord, query: String, artworkURL: URL?) {
        titleLabel.attributedText = SearchHighlightHelper.attributedString(
            text: track.title.sanitizedTrackTitle, query: query, font: .systemFont(ofSize: 16), color: .label,
        )

        let subtitle = [track.artistName, track.albumTitle].filter { !$0.isEmpty }.joined(separator: " · ")
        subtitleLabel.attributedText = SearchHighlightHelper.attributedString(
            text: subtitle, query: query, font: .systemFont(ofSize: 13), color: .secondaryLabel,
        )

        let seconds = Int(track.durationSeconds)
        trailingLabel.text = seconds > 0 ? formattedDuration(seconds: seconds) : nil
        artworkView.loadImage(url: artworkURL)
    }
}
