//
//  DownloadProgressCell.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import GlyphixTextFx
import SnapKit
import Then
import UIKit

final class DownloadProgressCell: TableBaseCell {
    static let reuseID = "DownloadProgressCell"

    private let artworkView = AmImageView().then { $0.configure(placeholder: "music.note", cornerRadius: 6) }
    private let titleLabel = UILabel().then { $0.font = .systemFont(ofSize: 16); $0.textColor = .label }
    private let subtitleLabel = GlyphixTextLabel().then {
        $0.font = .systemFont(ofSize: 13)
        $0.textColor = .secondaryLabel
        $0.isBlurEffectEnabled = false
        $0.isSmoothRenderingEnabled = false
        $0.countsDown = true
        $0.clipsToBounds = false
    }

    private let progressLabel = GlyphixTextLabel().then {
        $0.font = .monospacedDigitSystemFont(ofSize: 14, weight: .medium)
        $0.textColor = .tintColor
        $0.isBlurEffectEnabled = false
        $0.isSmoothRenderingEnabled = false
        $0.countsDown = true
        $0.clipsToBounds = false
    }

    private let progressBackground = UIView()

    private var currentProgress: Double = 0

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        artworkView.reset()
        titleLabel.text = nil
        subtitleLabel.text = ""
        subtitleLabel.textColor = .secondaryLabel
        progressLabel.text = ""
        progressLabel.textColor = .tintColor
        currentProgress = 0
    }

    func update(with task: ActiveDownloadTask, animated: Bool = false) {
        titleLabel.text = task.title.sanitizedTrackTitle

        var subtitle = task.artistName
        switch task.state {
        case .waiting: subtitle += " · \(String(localized: "Waiting…"))"
        case .waitingForNetwork: subtitle += " · \(String(localized: "Waiting for Network…"))"
        case .resolving: subtitle += " · \(String(localized: "Preparing…"))"
        case .finalizing: subtitle += " · \(String(localized: "Finalizing…"))"
        case .paused: subtitle += " · \(String(localized: "Paused"))"
        case .failed: subtitle += " · \(String(localized: "Failed"))"
        case .downloading:
            if task.speed > 0 {
                subtitle += " · \(ByteCountFormatter.string(fromByteCount: task.speed, countStyle: .file))/s"
            }
        }
        subtitleLabel.text = subtitle
        subtitleLabel.textColor = task.state == .failed ? .systemRed : .secondaryLabel

        switch task.state {
        case .waiting, .waitingForNetwork: progressLabel.text = ""
        case .resolving: progressLabel.text = "…"
        case .finalizing: progressLabel.text = "…"
        case .failed: progressLabel.text = "!"
        case .downloading, .paused:
            progressLabel.text = task.progress >= 0 ? "\(Int(task.progress * 100))%" : ""
        }
        progressLabel.textColor = task.state == .failed ? .systemRed : .tintColor

        artworkView.loadImage(url: task.artworkURL)

        currentProgress = task.progress
        setNeedsLayout()
        if animated {
            Interface.smoothSpringAnimate { self.layoutIfNeeded() }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = contentView.bounds.width * CGFloat(max(currentProgress, 0))
        progressBackground.frame = CGRect(x: 0, y: 0, width: width, height: contentView.bounds.height)
    }
}

private extension DownloadProgressCell {
    func setupViews() {
        contentView.addSubview(progressBackground)
        progressBackground.backgroundColor = UIColor.tintColor.withAlphaComponent(0.1)

        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel]).then {
            $0.axis = .vertical
            $0.spacing = InterfaceStyle.Spacing.xSmall
        }

        let row = UIStackView(arrangedSubviews: [artworkView, textStack, progressLabel]).then {
            $0.axis = .horizontal
            $0.spacing = InterfaceStyle.Spacing.small
            $0.alignment = .center
        }

        contentView.addSubview(row)
        artworkView.snp.makeConstraints { $0.size.equalTo(44) }
        progressLabel.snp.makeConstraints { $0.width.equalTo(50) }
        progressLabel.setContentHuggingPriority(.required, for: .horizontal)
        progressLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        row.snp.makeConstraints {
            $0.edges.equalToSuperview().inset(
                InterfaceStyle.Insets.symmetric(
                    vertical: InterfaceStyle.Spacing.xSmall,
                    horizontal: InterfaceStyle.Spacing.small,
                ),
            )
        }
    }
}
