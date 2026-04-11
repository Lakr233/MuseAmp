//
//  LyricTimelineCell.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import SnapKit
import Then
import UIKit

final class LyricTimelineCell: UITableViewCell {
    enum LineState {
        case inapplicable
        case played
        case active
        case upcoming
    }

    static let reuseIdentifier = "LyricTimelineCell"

    private let tapHighlightView = UIView().then {
        $0.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        $0.layer.cornerCurve = .continuous
        $0.layer.cornerRadius = LyricTimelineLineStyle.tapHighlightCornerRadius
        $0.alpha = 0
        $0.isUserInteractionEnabled = false
    }

    private let lyricLabel = UILabel().then {
        $0.numberOfLines = 0
        $0.textAlignment = .natural
        $0.lineBreakMode = .byWordWrapping
        $0.textColor = .white
        $0.font = LyricTimelineLineStyle.textFont
        $0.adjustsFontForContentSizeCategory = true
        $0.isUserInteractionEnabled = false
        $0.clipsToBounds = false
    }

    private var currentState: LineState?
    private var seekTime: TimeInterval?
    private var onTap: (TimeInterval) -> Void = { _ in }
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .light)
    private var leadingConstraint: Constraint?
    private var trailingConstraint: Constraint?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        selectionStyle = .none
        clipsToBounds = false
        contentView.clipsToBounds = false

        contentView.addSubview(tapHighlightView)
        contentView.addSubview(lyricLabel)

        tapHighlightView.snp.makeConstraints { make in
            make.edges.equalTo(lyricLabel).inset(-8)
        }

        lyricLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().inset(LyricTimelineAnimation.plainRevealTranslationY / 2)
            make.bottom.equalToSuperview().inset(LyricTimelineAnimation.plainRevealTranslationY / 2)
            leadingConstraint = make.leading.equalToSuperview().offset(16).constraint
            trailingConstraint = make.trailing.equalToSuperview().offset(-16).constraint
        }

        let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleCellTap))
        contentView.addGestureRecognizer(tapRecognizer)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        selectedBackgroundView?.isHidden = true
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        currentState = nil
        seekTime = nil
        onTap = { _ in }
        lyricLabel.text = nil
        lyricLabel.alpha = 1
        tapHighlightView.alpha = 0
        alpha = 1
    }

    func configure(
        text: String,
        horizontalInset: CGFloat,
        state: LineState,
        seekTime: TimeInterval?,
        onTap: @escaping (TimeInterval) -> Void = { _ in },
    ) {
        lyricLabel.text = text.isEmpty ? " " : text
        self.seekTime = seekTime.map { max($0, 0) }
        self.onTap = onTap
        leadingConstraint?.update(offset: horizontalInset)
        trailingConstraint?.update(offset: -horizontalInset)
        applyState(state)
    }

    func applyState(_ state: LineState) {
        guard currentState != state else { return }
        currentState = state
        switch state {
        case .inapplicable:
            lyricLabel.alpha = LyricTimelineLineStyle.activeAlpha
        case .played:
            lyricLabel.alpha = LyricTimelineLineStyle.inactiveAlpha
        case .active:
            lyricLabel.alpha = LyricTimelineLineStyle.activeAlpha
        case .upcoming:
            lyricLabel.alpha = LyricTimelineLineStyle.inactiveAlpha
        }
    }

    func performIndirectTapSelection() {
        guard let seekTime else { return }
        feedbackGenerator.prepare()
        setTapHighlightVisible(true)
        onTap(seekTime)
        feedbackGenerator.impactOccurred()
        setTapHighlightVisible(false)
    }

    @objc
    private func handleCellTap() {
        guard let seekTime else { return }
        feedbackGenerator.prepare()
        setTapHighlightVisible(true)
        onTap(seekTime)
        feedbackGenerator.impactOccurred()
        setTapHighlightVisible(false)
    }

    private func setTapHighlightVisible(_: Bool) {
        tapHighlightView.layer.removeAllAnimations()
        tapHighlightView.alpha = 0
    }
}
