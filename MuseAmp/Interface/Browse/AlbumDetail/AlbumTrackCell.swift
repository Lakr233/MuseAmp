import SnapKit
import UIKit

@MainActor
class AlbumTrackCell: TableBaseCell {
    private nonisolated enum Layout {
        static let horizontalInset: CGFloat = 16
        static let rowInset: CGFloat = 12
        static let iconSize: CGFloat = 16
        static let titleSpacing: CGFloat = 12
        static let badgeSpacing: CGFloat = 4
        static let durationSpacing: CGFloat = 8
    }

    class var reuseID: String {
        String(describing: self)
    }

    private let numberImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.tintColor = PlatformInterfacePalette.tertiaryText
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16, weight: .regular)
        label.numberOfLines = 1
        return label
    }()

    private let explicitBadge: UIImageView = {
        let imageView = UIImageView(image: UIImage(systemName: "e.square.fill"))
        imageView.tintColor = PlatformInterfacePalette.tertiaryText
        imageView.contentMode = .scaleAspectFit
        imageView.isHidden = true
        return imageView
    }()

    private let downloadedBadge: UIImageView = {
        let imageView = UIImageView(image: UIImage(systemName: "arrow.down.to.line.circle.fill"))
        imageView.tintColor = .tintColor
        imageView.contentMode = .scaleAspectFit
        imageView.isHidden = true
        return imageView
    }()

    private let highlightView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.tintColor.withAlphaComponent(0.1)
        view.alpha = 0
        view.isUserInteractionEnabled = false
        return view
    }()

    private let durationLabel: UILabel = {
        let label = UILabel()
        label.font = .monospacedDigitSystemFont(ofSize: 14, weight: .regular)
        label.textColor = PlatformInterfacePalette.tertiaryText
        label.textAlignment = .right
        return label
    }()

    private var numberLeadingConstraint: Constraint?
    private var downloadedTrailingConstraint: Constraint?
    private var durationTrailingConstraint: Constraint?
    private var durationToDownloadedConstraint: Constraint?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        let titleStack = UIStackView(arrangedSubviews: [titleLabel, explicitBadge])
        titleStack.axis = .horizontal
        titleStack.spacing = Layout.badgeSpacing
        titleStack.alignment = .center

        contentView.addSubview(highlightView)
        contentView.addSubview(numberImageView)
        contentView.addSubview(titleStack)
        contentView.addSubview(durationLabel)
        contentView.addSubview(downloadedBadge)

        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        durationLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        durationLabel.setContentHuggingPriority(.required, for: .horizontal)

        highlightView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        numberImageView.snp.makeConstraints { make in
            numberLeadingConstraint = make.leading.equalToSuperview().offset(Layout.horizontalInset).constraint
            make.centerY.equalTo(titleLabel.snp.centerY)
            make.size.equalTo(Layout.iconSize)
        }
        titleStack.snp.makeConstraints { make in
            make.leading.equalTo(numberImageView.snp.trailing).offset(Layout.titleSpacing)
            make.top.equalToSuperview().offset(Layout.rowInset)
            make.bottom.equalToSuperview().offset(-Layout.rowInset)
        }
        explicitBadge.snp.makeConstraints { make in
            make.size.equalTo(Layout.iconSize)
        }
        downloadedBadge.snp.makeConstraints { make in
            downloadedTrailingConstraint = make.trailing.equalToSuperview().offset(-Layout.horizontalInset).constraint
            make.centerY.equalTo(titleLabel.snp.centerY)
            make.size.equalTo(Layout.iconSize)
        }
        durationLabel.snp.makeConstraints { make in
            make.leading.greaterThanOrEqualTo(titleStack.snp.trailing).offset(Layout.durationSpacing)
            make.width.greaterThanOrEqualTo(36)
            make.firstBaseline.equalTo(titleLabel.snp.firstBaseline)
            durationTrailingConstraint = make.trailing.equalTo(contentView.snp.trailing).offset(-Layout.horizontalInset).constraint
        }
        durationLabel.snp.prepareConstraints { make in
            durationToDownloadedConstraint = make.trailing.equalTo(downloadedBadge.snp.leading).offset(-Layout.durationSpacing).constraint
        }
        updateHorizontalInsets()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.horizontalSizeClass != previousTraitCollection?.horizontalSizeClass else { return }
        updateHorizontalInsets()
    }

    private func updateHorizontalInsets() {
        let inset: CGFloat = traitCollection.horizontalSizeClass == .regular
            ? InterfaceStyle.Spacing.medium
            : Layout.horizontalInset
        numberLeadingConstraint?.update(offset: inset)
        downloadedTrailingConstraint?.update(offset: -inset)
        durationTrailingConstraint?.update(offset: -inset)
    }

    func configure(content: AlbumTrackCellContent) {
        if content.isPlaying {
            numberImageView.image = playingImage()
        } else {
            numberImageView.image = trackNumberImage(content.number)
        }
        titleLabel.text = content.title
        explicitBadge.isHidden = !content.isExplicit
        durationLabel.text = content.durationText
        setDownloadedState(content.isDownloaded)

        if content.isHighlighted || content.isPlaying {
            titleLabel.font = .systemFont(ofSize: 16, weight: .bold)
            titleLabel.textColor = .tintColor
            numberImageView.tintColor = .tintColor
            durationLabel.textColor = .tintColor
        } else {
            titleLabel.font = .systemFont(ofSize: 16, weight: .regular)
            titleLabel.textColor = .label
            numberImageView.tintColor = PlatformInterfacePalette.tertiaryText
            durationLabel.textColor = PlatformInterfacePalette.tertiaryText
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        highlightView.layer.removeAllAnimations()
        highlightView.alpha = 0
        numberImageView.image = nil
        numberImageView.tintColor = PlatformInterfacePalette.tertiaryText
        titleLabel.text = nil
        titleLabel.font = .systemFont(ofSize: 16, weight: .regular)
        titleLabel.textColor = .label
        explicitBadge.isHidden = true
        setDownloadedState(false)
        durationLabel.text = nil
        durationLabel.textColor = PlatformInterfacePalette.tertiaryText
    }

    override func setHighlighted(_ highlighted: Bool, animated: Bool) {
        super.setHighlighted(highlighted, animated: animated)
        highlightView.layer.removeAllAnimations()
        if highlighted {
            highlightView.alpha = 1
        } else {
            Interface.animate(duration: 0.25) {
                self.highlightView.alpha = 0
            }
        }
    }

    private func setDownloadedState(_ downloaded: Bool) {
        downloadedBadge.isHidden = !downloaded
        if downloaded {
            durationTrailingConstraint?.deactivate()
            durationToDownloadedConstraint?.activate()
        } else {
            durationToDownloadedConstraint?.deactivate()
            durationTrailingConstraint?.activate()
        }
    }

    private func trackNumberImage(_ number: Int) -> UIImage? {
        let configuration = UIImage.SymbolConfiguration(font: .systemFont(ofSize: 15, weight: .regular))
        return UIImage(systemName: "\(number).circle.fill", withConfiguration: configuration)
    }

    private func playingImage() -> UIImage? {
        let configuration = UIImage.SymbolConfiguration(font: .systemFont(ofSize: 15, weight: .bold))
        return UIImage(systemName: "play.fill", withConfiguration: configuration)
    }
}
