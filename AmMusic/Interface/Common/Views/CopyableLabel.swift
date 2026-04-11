//
//  CopyableLabel.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import UIKit

final class CopyableLabel: UILabel, UIEditMenuInteractionDelegate {
    private var editMenuInteraction: UIEditMenuInteraction?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = true
        let interaction = UIEditMenuInteraction(delegate: self)
        editMenuInteraction = interaction
        addInteraction(interaction)
        addGestureRecognizer(
            UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:))),
        )
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override var canBecomeFirstResponder: Bool {
        true
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, let text, !text.isEmpty else { return }
        becomeFirstResponder()
        let point = gesture.location(in: self)
        let config = UIEditMenuConfiguration(identifier: nil, sourcePoint: point)
        editMenuInteraction?.presentEditMenu(with: config)
    }

    func editMenuInteraction(
        _: UIEditMenuInteraction,
        menuFor _: UIEditMenuConfiguration,
        suggestedActions _: [UIMenuElement],
    ) -> UIMenu? {
        let copy = UIAction(title: String(localized: "Copy")) { [weak self] _ in
            UIPasteboard.general.string = self?.text
        }
        return UIMenu(children: [copy])
    }
}
