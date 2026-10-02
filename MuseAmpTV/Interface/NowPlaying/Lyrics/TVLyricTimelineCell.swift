import SnapKit
import UIKit

nonisolated enum TVLyricLineStyle {
    static let textFont = UIFontMetrics(forTextStyle: .title2).scaledFont(
        for: .systemFont(ofSize: TVNowPlayingLayout.lyricFontSize, weight: .bold),
    )
    static let activeAlpha: CGFloat = 1.0
    static let inactiveAlpha: CGFloat = 0.25
    static let estimatedLineHeight = ceil(textFont.lineHeight)
}

@MainActor
final class TVLyricTimelineCell: UITableViewCell {
    private let lyricLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 0
        label.textAlignment = .natural
        label.lineBreakMode = .byWordWrapping
        label.textColor = .white
        label.font = TVLyricLineStyle.textFont
        label.adjustsFontForContentSizeCategory = true
        label.isUserInteractionEnabled = false
        return label
    }()

    private var isActive: Bool?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        selectionStyle = .none
        isUserInteractionEnabled = false
        focusStyle = .custom

        contentView.addSubview(lyricLabel)
        lyricLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(TVNowPlayingLayout.spacing8)
            make.bottom.equalToSuperview().offset(-TVNowPlayingLayout.spacing8)
            make.leading.equalToSuperview().offset(TVNowPlayingLayout.spacing64)
            make.trailing.equalToSuperview().offset(-TVNowPlayingLayout.spacing64)
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override var canBecomeFocused: Bool {
        false
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        isActive = nil
        lyricLabel.text = nil
        lyricLabel.alpha = 0
    }

    func configure(text: String, isActive: Bool) {
        lyricLabel.text = text.isEmpty ? " " : text
        applyActive(isActive)
    }

    func applyActive(_ active: Bool) {
        guard isActive != active else { return }
        let shouldAnimate = isActive != nil
        isActive = active

        let targetAlpha: CGFloat = active
            ? TVLyricLineStyle.activeAlpha
            : TVLyricLineStyle.inactiveAlpha

        if shouldAnimate {
            Interface.smoothSpringAnimate {
                self.lyricLabel.alpha = targetAlpha
            }
        } else {
            lyricLabel.alpha = targetAlpha
        }
    }
}
