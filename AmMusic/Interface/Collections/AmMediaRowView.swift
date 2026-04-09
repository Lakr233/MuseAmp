import SnapKit
import Then
import UIKit

final class AmMediaRowView: UIView {
    private let artworkView = AmImageView()
    private let titleLabel = UILabel().then {
        $0.font = .systemFont(ofSize: 16)
    }

    private let subtitleLabel = UILabel().then {
        $0.font = .systemFont(ofSize: 13)
        $0.textColor = .secondaryLabel
        $0.numberOfLines = 1
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    func configure(title: String, subtitle: String?, placeholderIcon: String, roundArtwork: Bool) {
        titleLabel.attributedText = nil
        titleLabel.text = title
        subtitleLabel.attributedText = nil
        subtitleLabel.text = subtitle
        subtitleLabel.isHidden = subtitle == nil
        artworkView.configure(placeholder: placeholderIcon, cornerRadius: roundArtwork ? 22 : 6)
    }

    func setAttributedTitle(_ attributedTitle: NSAttributedString) {
        titleLabel.attributedText = attributedTitle
    }

    func setAttributedSubtitle(_ attributedSubtitle: NSAttributedString?) {
        subtitleLabel.attributedText = attributedSubtitle
        subtitleLabel.isHidden = attributedSubtitle == nil
    }

    func loadArtwork(url: URL?) {
        artworkView.loadImage(url: url)
    }

    func setArtworkImage(_ image: UIImage) {
        artworkView.setImage(image)
    }

    func resetArtwork() {
        artworkView.reset()
    }

    func prepareForReuse() {
        artworkView.reset()
        titleLabel.text = nil
        subtitleLabel.text = nil
        subtitleLabel.isHidden = false
    }

    private func setup() {
        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel]).then {
            $0.axis = .vertical
            $0.spacing = InterfaceStyle.Spacing.xSmall
            $0.alignment = .fill
        }

        let row = UIStackView(arrangedSubviews: [artworkView, textStack]).then {
            $0.axis = .horizontal
            $0.spacing = InterfaceStyle.Spacing.small
            $0.alignment = .top
        }

        addSubview(row)

        artworkView.snp.makeConstraints { make in
            make.size.equalTo(44)
        }

        row.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }
}
