import SnapKit
import UIKit

@MainActor
class LyricTimelineCell: UITableViewCell {
    private let lyricLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 0
        label.textAlignment = .natural
        label.lineBreakMode = .byWordWrapping
        label.textColor = .white
        label.font = LyricTimelineLineStyle.textFont
        label.adjustsFontForContentSizeCategory = true
        label.isUserInteractionEnabled = false
        label.shadowColor = nil
        label.shadowOffset = .zero
        label.layer.shadowOpacity = 0
        label.alpha = 0
        return label
    }()

    private var isActive: Bool?
    private var leadingConstraint: Constraint?
    private var trailingConstraint: Constraint?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        selectionStyle = .none

        contentView.addSubview(lyricLabel)

        let verticalInset = LyricTimelineAnimation.plainRevealTranslationY / 2

        lyricLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(verticalInset)
            make.bottom.equalToSuperview().offset(-verticalInset)
            leadingConstraint = make.leading.equalToSuperview().offset(16).constraint
            trailingConstraint = make.trailing.equalToSuperview().offset(-16).constraint
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        isActive = nil
        lyricLabel.text = nil
        lyricLabel.alpha = 0
        // The content fade-in animates the cell's own alpha; recycled cells
        // must not inherit a half-finished fade from the previous row.
        alpha = 1
    }

    func configure(text: String, horizontalInset: CGFloat, isActive: Bool) {
        lyricLabel.text = text.isEmpty ? " " : text
        leadingConstraint?.update(offset: horizontalInset)
        trailingConstraint?.update(offset: -horizontalInset)
        applyActive(isActive)
    }

    func applyActive(_ active: Bool) {
        guard isActive != active else { return }
        let shouldAnimate = isActive != nil
        isActive = active

        let targetAlpha: CGFloat = active
            ? LyricTimelineLineStyle.activeAlpha
            : LyricTimelineLineStyle.inactiveAlpha

        if shouldAnimate {
            Interface.smoothSpringAnimate {
                self.lyricLabel.alpha = targetAlpha
            }
        } else {
            lyricLabel.alpha = targetAlpha
        }
    }
}
