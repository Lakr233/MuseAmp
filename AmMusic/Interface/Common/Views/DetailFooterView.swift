//
//  DetailFooterView.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import SnapKit
import Then
import UIKit

final class DetailFooterView: UIView {
    var infoText: String? {
        get { infoLabel.text }
        set { infoLabel.text = newValue }
    }

    private let listEndDecorationView = ListEndDecorationView()

    private let infoLabel = UILabel().then {
        $0.font = .preferredFont(forTextStyle: .footnote)
        $0.textColor = .secondaryLabel
        $0.numberOfLines = 0
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        addSubview(listEndDecorationView)
        addSubview(infoLabel)

        listEndDecorationView.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(InterfaceStyle.Spacing.small).priority(.high)
            make.leading.trailing.equalToSuperview().inset(56).priority(.high)
        }

        infoLabel.snp.makeConstraints { make in
            make.top.equalTo(listEndDecorationView.snp.bottom).offset(InterfaceStyle.Spacing.medium).priority(.high)
            make.leading.trailing.equalToSuperview().inset(20).priority(.high)
            make.bottom.equalToSuperview().inset(InterfaceStyle.Spacing.large).priority(.high)
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }
}
