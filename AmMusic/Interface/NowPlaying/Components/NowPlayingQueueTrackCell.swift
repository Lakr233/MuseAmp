import SnapKit
import Then
import UIKit

final class NowPlayingQueueTrackCell: TableBaseCell {
    enum AccessoryStyle {
        case more
        case reorder
    }

    static let reuseID = "NowPlayingQueueTrackCell"

    private enum Layout {
        static let horizontalInset: CGFloat = 16
        static let verticalInset: CGFloat = 4
        static let artworkSize: CGFloat = 48
        static let separatorLeadingInset: CGFloat = 76
    }

    private let artworkView = AmImageView().then {
        $0.configure(placeholder: "music.note", cornerRadius: 4)
    }

    private let titleLabel = UILabel().then {
        $0.font = .systemFont(ofSize: 17, weight: .regular)
        $0.textColor = .label
        $0.numberOfLines = 1
    }

    private let subtitleLabel = UILabel().then {
        $0.font = .systemFont(ofSize: 13, weight: .regular)
        $0.textColor = .secondaryLabel
        $0.numberOfLines = 1
    }

    private let accessoryImageView = UIImageView().then {
        $0.contentMode = .center
        $0.tintColor = .secondaryLabel
    }

    private let separatorView = UIView().then {
        $0.backgroundColor = UIColor.separator.withAlphaComponent(0.5)
    }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        let labelsStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel]).then {
            $0.axis = .vertical
            $0.alignment = .fill
            $0.spacing = 2
        }

        let rowStack = UIStackView(arrangedSubviews: [artworkView, labelsStack, accessoryImageView]).then {
            $0.axis = .horizontal
            $0.alignment = .center
            $0.spacing = 8
        }

        contentView.addSubview(rowStack)
        contentView.addSubview(separatorView)

        artworkView.snp.makeConstraints { make in
            make.size.equalTo(Layout.artworkSize)
        }

        accessoryImageView.snp.makeConstraints { make in
            make.size.equalTo(24)
        }

        rowStack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(
                UIEdgeInsets(
                    top: Layout.verticalInset,
                    left: Layout.horizontalInset,
                    bottom: Layout.verticalInset,
                    right: Layout.horizontalInset
                )
            )
        }

        separatorView.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(Layout.separatorLeadingInset)
            make.trailing.bottom.equalToSuperview()
            make.height.equalTo(0.5)
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        artworkView.reset()
        titleLabel.text = nil
        subtitleLabel.text = nil
        accessoryImageView.image = nil
        separatorView.isHidden = false
    }

    func configure(
        track: PlaybackTrack,
        accessoryStyle: AccessoryStyle,
        hidesSeparator: Bool
    ) {
        titleLabel.text = track.title
        subtitleLabel.text = track.artistName
        artworkView.loadImage(url: track.artworkURL)
        separatorView.isHidden = hidesSeparator

        let symbolName: String
        let symbolConfiguration: UIImage.SymbolConfiguration

        switch accessoryStyle {
        case .more:
            symbolName = "ellipsis"
            symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
        case .reorder:
            symbolName = "line.3.horizontal"
            symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        }

        accessoryImageView.image = UIImage(
            systemName: symbolName,
            withConfiguration: symbolConfiguration
        )
    }
}
