import AmMusicKit
import SnapKit
import Then
import UIKit

final class AlbumTrackCell: TableBaseCell {
    static let reuseID = "AlbumTrackCell"

    private enum Layout {
        static let horizontalInset: CGFloat = 16
        static let rowInset: CGFloat = 12
        static let iconSize: CGFloat = 16
        static let titleSpacing: CGFloat = 12
        static let badgeSpacing: CGFloat = 4
        static let durationSpacing: CGFloat = 8
    }

    private let numberImageView = UIImageView().then {
        $0.tintColor = .tertiaryLabel
        $0.contentMode = .scaleAspectFit
    }

    private let titleLabel = UILabel().then {
        $0.font = .systemFont(ofSize: 16, weight: .regular)
        $0.numberOfLines = 1
    }

    private let explicitBadge = UIImageView().then {
        $0.image = UIImage(systemName: "e.square.fill")
        $0.tintColor = .tertiaryLabel
        $0.contentMode = .scaleAspectFit
        $0.isHidden = true
    }

    private let downloadedBadge = UIImageView().then {
        $0.image = UIImage(systemName: "arrow.down.to.line.circle.fill")
        $0.tintColor = .tintColor
        $0.contentMode = .scaleAspectFit
        $0.isHidden = true
    }

    private let highlightView = UIView().then {
        $0.backgroundColor = UIColor.tintColor.withAlphaComponent(0.1)
        $0.alpha = 0
        $0.isUserInteractionEnabled = false
    }

    private let durationLabel = UILabel().then {
        $0.font = .monospacedDigitSystemFont(ofSize: 14, weight: .regular)
        $0.textColor = .tertiaryLabel
        $0.textAlignment = .right
    }

    private var durationTrailingConstraint: Constraint?
    private var durationToDownloadedConstraint: Constraint?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        let titleStack = UIStackView(arrangedSubviews: [titleLabel, explicitBadge]).then {
            $0.axis = .horizontal
            $0.spacing = Layout.badgeSpacing
            $0.alignment = .center
        }

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
            make.leading.equalToSuperview().offset(Layout.horizontalInset)
            make.centerY.equalTo(titleLabel)
            make.size.equalTo(Layout.iconSize)
        }

        titleStack.snp.makeConstraints { make in
            make.leading.equalTo(numberImageView.snp.trailing).offset(Layout.titleSpacing)
            make.top.equalToSuperview().inset(Layout.rowInset)
            make.bottom.equalToSuperview().inset(Layout.rowInset)
        }

        explicitBadge.snp.makeConstraints { make in
            make.size.equalTo(Layout.iconSize)
        }

        downloadedBadge.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(Layout.horizontalInset)
            make.centerY.equalTo(titleLabel)
            make.size.equalTo(Layout.iconSize)
        }

        durationLabel.snp.makeConstraints { make in
            make.leading.greaterThanOrEqualTo(titleStack.snp.trailing).offset(Layout.durationSpacing)
            durationTrailingConstraint = make.trailing.equalToSuperview().inset(Layout.horizontalInset).constraint
            durationToDownloadedConstraint = make.trailing.equalTo(downloadedBadge.snp.leading).offset(-Layout.durationSpacing).constraint
            make.width.greaterThanOrEqualTo(36)
            make.firstBaseline.equalTo(titleLabel.snp.firstBaseline)
        }

        setDownloadedState(false)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        highlightView.layer.removeAllAnimations()
        highlightView.alpha = 0
        numberImageView.image = nil
        numberImageView.tintColor = .tertiaryLabel
        titleLabel.text = nil
        titleLabel.font = .systemFont(ofSize: 16, weight: .regular)
        titleLabel.textColor = .label
        explicitBadge.isHidden = true
        setDownloadedState(false)
        durationLabel.text = nil
        durationLabel.textColor = .tertiaryLabel
    }

    func configure(number: Int, track: CatalogSong, highlighted: Bool = false, downloaded: Bool = false) {
        numberImageView.image = trackNumberImage(number)
        titleLabel.text = track.attributes.name

        let isExplicit = track.attributes.contentRating == "explicit"
        explicitBadge.isHidden = !isExplicit
        setDownloadedState(downloaded)

        durationLabel.text = track.attributes.durationInMillis.map { formattedDuration(millis: $0) }

        if highlighted {
            titleLabel.font = .systemFont(ofSize: 16, weight: .bold)
            titleLabel.textColor = .tintColor
            numberImageView.tintColor = .tintColor
            durationLabel.textColor = .tintColor
        }
    }

    private func setDownloadedState(_ downloaded: Bool) {
        downloadedBadge.isHidden = !downloaded
        durationTrailingConstraint?.isActive = !downloaded
        durationToDownloadedConstraint?.isActive = downloaded
    }

    private func trackNumberImage(_ number: Int) -> UIImage? {
        let configuration = UIImage.SymbolConfiguration(font: .systemFont(ofSize: 15, weight: .regular))
        return UIImage(systemName: "\(number).circle", withConfiguration: configuration)
    }

    func animateTapHighlight() {
        highlightView.layer.removeAllAnimations()
        highlightView.alpha = 1
        InterfaceAnimation.animate(duration: 0.25, options: [.curveEaseOut, .beginFromCurrentState]) {
            self.highlightView.alpha = 0
        }
    }
}
