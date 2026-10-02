import SnapKit
import UIKit

@MainActor
final class DownloadProgressCell: TableBaseCell {
    static let reuseID = "DownloadProgressCell"

    private let artworkView: MuseAmpImageView = {
        let view = MuseAmpImageView()
        view.configure(placeholder: "music.note", cornerRadius: 6)
        return view
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16)
        label.textColor = .label
        return label
    }()

    private let subtitleLabel: AnimatedTextLabel = {
        let label = AnimatedTextLabel()
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabel
        label.clipsToBounds = false
        return label
    }()

    private let progressLabel: AnimatedTextLabel = {
        let label = AnimatedTextLabel()
        label.font = .monospacedDigitSystemFont(ofSize: 14, weight: .medium)
        label.textColor = .tintColor
        label.clipsToBounds = false
        return label
    }()

    private let progressBackground = UIView()
    private var currentProgress: Double = 0

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        artworkView.reset()
        titleLabel.text = nil
        subtitleLabel.text = ""
        subtitleLabel.textColor = .secondaryLabel
        progressLabel.text = ""
        progressLabel.textColor = .tintColor
        currentProgress = 0
    }

    func update(with content: AMDownloadProgressContent, animated: Bool = false) {
        titleLabel.text = content.title
        subtitleLabel.text = content.subtitle
        subtitleLabel.textColor = content.isFailed ? .systemRed : .secondaryLabel
        progressLabel.text = content.progressText
        progressLabel.textColor = content.isFailed ? .systemRed : .tintColor
        artworkView.loadImage(url: content.artworkURL)

        currentProgress = content.progress
        setNeedsLayout()
        if animated {
            Interface.smoothSpringAnimate { self.layoutIfNeeded() }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = contentView.bounds.width * CGFloat(max(currentProgress, 0))
        progressBackground.frame = CGRect(x: 0, y: 0, width: width, height: contentView.bounds.height)
    }

    private func setupViews() {
        contentView.addSubview(progressBackground)
        progressBackground.backgroundColor = UIColor.tintColor.withAlphaComponent(0.1)

        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textStack.axis = .vertical
        textStack.spacing = InterfaceStyle.Spacing.xSmall

        let row = UIStackView(arrangedSubviews: [artworkView, textStack, progressLabel])
        row.axis = .horizontal
        row.spacing = InterfaceStyle.Spacing.small
        row.alignment = .center

        contentView.addSubview(row)

        artworkView.snp.makeConstraints { make in
            make.size.equalTo(44)
        }
        row.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(InterfaceStyle.Spacing.xSmall)
            make.leading.equalToSuperview().offset(InterfaceStyle.Spacing.small)
            make.trailing.equalToSuperview().offset(-InterfaceStyle.Spacing.small)
            make.bottom.equalToSuperview().offset(-InterfaceStyle.Spacing.xSmall)
        }
        progressLabel.snp.makeConstraints { make in
            make.width.equalTo(50)
        }

        progressLabel.setContentHuggingPriority(.required, for: .horizontal)
        progressLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
    }
}
