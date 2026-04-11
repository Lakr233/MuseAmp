//
//  ListEndDecorationView.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import SnapKit
import Then
import UIKit

final class ListEndDecorationView: UIView {
    private let decorationColor = UIColor.gray.withAlphaComponent(0.1)

    private let leftLine = UIView()

    private let centerDot = UIView()

    private let rightLine = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)

        leftLine.backgroundColor = decorationColor
        centerDot.backgroundColor = decorationColor
        centerDot.layer.cornerRadius = 2
        rightLine.backgroundColor = decorationColor

        let stack = UIStackView(arrangedSubviews: [leftLine, centerDot, rightLine]).then {
            $0.axis = .horizontal
            $0.alignment = .center
            $0.spacing = 14
            $0.distribution = .fill
        }

        addSubview(stack)

        stack.snp.makeConstraints { make in
            make.edges.equalToSuperview().priority(.high)
        }

        leftLine.snp.makeConstraints { make in
            make.height.equalTo(1).priority(.high)
        }

        centerDot.snp.makeConstraints { make in
            make.size.equalTo(4).priority(.high)
        }

        rightLine.snp.makeConstraints { make in
            make.height.equalTo(1).priority(.high)
            make.width.equalTo(leftLine).priority(.high)
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }
}
