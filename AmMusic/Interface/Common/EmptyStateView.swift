import SnapKit
import Then
import UIKit

final class EmptyStateView: UIView {
    private let iconView: UIImageView
    private let titleLabel: UILabel
    private let subtitleLabel: UILabel

    init(icon: String, title: String, subtitle: String) {
        iconView = UIImageView(image: UIImage(systemName: icon)).then {
            $0.tintColor = .quaternaryLabel
            $0.contentMode = .scaleAspectFit
        }

        titleLabel = UILabel().then {
            $0.text = title
            $0.font = .systemFont(ofSize: 20, weight: .semibold)
            $0.textColor = .secondaryLabel
            $0.textAlignment = .center
        }

        subtitleLabel = UILabel().then {
            $0.text = subtitle
            $0.font = .preferredFont(forTextStyle: .subheadline)
            $0.textColor = .tertiaryLabel
            $0.textAlignment = .center
        }

        super.init(frame: .zero)

        let stack = UIStackView(arrangedSubviews: [iconView, titleLabel, subtitleLabel]).then {
            $0.axis = .vertical
            $0.spacing = InterfaceStyle.Spacing.xSmall
            $0.alignment = .center
            $0.setCustomSpacing(InterfaceStyle.Spacing.small, after: iconView)
        }

        addSubview(stack)

        iconView.snp.makeConstraints { make in
            make.size.equalTo(56)
        }

        stack.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }
}
