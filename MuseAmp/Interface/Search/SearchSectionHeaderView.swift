import SnapKit
import UIKit

@MainActor
class SearchSectionHeaderView: UITableViewHeaderFooterView {
    class var reuseID: String {
        String(describing: self)
    }

    private lazy var accessoryButton: UIButton = {
        let button = UIButton(type: .system)
        button.titleLabel?.font = .systemFont(ofSize: 15)
        return button
    }()

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
                accessoryButton.snp.makeConstraints { make in
                    make.trailing.equalTo(contentView.layoutMarginsGuide.snp.trailing)
                    make.centerY.equalToSuperview()
                }
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
