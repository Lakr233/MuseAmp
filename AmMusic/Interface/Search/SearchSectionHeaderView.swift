//
//  SearchSectionHeaderView.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import Then
import UIKit

final class SearchSectionHeaderView: UITableViewHeaderFooterView {
    static let reuseID = "SearchSectionHeaderView"

    private lazy var accessoryButton = UIButton(type: .system).then {
        $0.titleLabel?.font = .systemFont(ofSize: 15)
    }

    private var hasAccessory = false

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    func configure(title: String, accessoryTitle: String? = nil) {
        var config = defaultContentConfiguration()
        config.text = title
        config.textProperties.font = .systemFont(ofSize: 20, weight: .bold)
        config.textProperties.color = .label
        contentConfiguration = config

        if let accessoryTitle {
            if !hasAccessory {
                hasAccessory = true
                contentView.addSubview(accessoryButton)
                accessoryButton.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    accessoryButton.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
                    accessoryButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
                ])
            }
            accessoryButton.setTitle(accessoryTitle, for: .normal)
            accessoryButton.isHidden = false
        } else {
            accessoryButton.isHidden = true
        }
    }

    func setAccessoryAction(_ action: UIAction) {
        accessoryButton.removeTarget(nil, action: nil, for: .allEvents)
        accessoryButton.addAction(action, for: .touchUpInside)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        accessoryButton.removeTarget(nil, action: nil, for: .allEvents)
        accessoryButton.isHidden = true
    }
}
