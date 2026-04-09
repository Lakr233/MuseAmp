import SnapKit
import Then
import UIKit

final class SearchSectionHeaderView: UIView {
    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .regular))
    private let titleLabel = UILabel().then {
        $0.font = .systemFont(ofSize: 20, weight: .bold)
        $0.textColor = .label
    }

    private lazy var accessoryButton = UIButton(type: .system).then {
        $0.titleLabel?.font = .systemFont(ofSize: 15)
        $0.isHidden = true
    }

    init(title: String, accessoryTitle: String? = nil) {
        super.init(frame: .zero)

        backgroundColor = .clear
        if #available(iOS 26.0, *) {
            // iOS 26 section headers already render with system material.
        } else {
            blurView.clipsToBounds = true
            addSubview(blurView)
            blurView.snp.makeConstraints { make in
                make.edges.equalToSuperview()
            }
        }
        addSubview(titleLabel)
        addSubview(accessoryButton)

        titleLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(16)
            make.top.bottom.equalToSuperview().inset(8)
        }
        accessoryButton.snp.makeConstraints { make in
            make.leading.greaterThanOrEqualTo(titleLabel.snp.trailing).offset(12)
            make.trailing.equalToSuperview().inset(16)
            make.centerY.equalTo(titleLabel)
        }

        titleLabel.text = title
        if let accessoryTitle {
            accessoryButton.setTitle(accessoryTitle, for: .normal)
            accessoryButton.isHidden = false
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    func setAccessoryAction(_ action: UIAction) {
        accessoryButton.removeTarget(nil, action: nil, for: .allEvents)
        accessoryButton.addAction(action, for: .touchUpInside)
        accessoryButton.isHidden = false
    }
}
