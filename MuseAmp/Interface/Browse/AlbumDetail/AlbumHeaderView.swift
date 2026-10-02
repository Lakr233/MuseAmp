import SnapKit
import UIKit

@MainActor
final class AlbumHeaderView: UIView {
    let artworkContainerView = UIView()

    var onPlayTapped: () -> Void = {}
    var onShuffleTapped: () -> Void = {}

    private let shadowContainer: UIView = {
        let view = UIView()
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.25
        view.layer.shadowRadius = 8
        view.layer.shadowOffset = .zero
        return view
    }()

    private let albumNameLabel: CopyableLabel = {
        let label = CopyableLabel()
        label.font = .systemFont(ofSize: 21, weight: .bold)
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    private let artistNameLabel: CopyableLabel = {
        let label = CopyableLabel()
        label.font = .systemFont(ofSize: 17, weight: .medium)
        label.textColor = .tintColor
        label.textAlignment = .center
        return label
    }()

    private let metaLabel: CopyableLabel = {
        let label = CopyableLabel()
        label.font = .preferredFont(forTextStyle: .caption1)
        label.textColor = PlatformInterfacePalette.secondaryText
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    private lazy var playButton = makeActionButton(systemImage: "play.fill")
    private lazy var shuffleButton = makeActionButton(systemImage: "shuffle")
    private let buttonStack = UIStackView()
    private let infoStack = UIStackView()
    private let contentStack = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    func configure(content: AlbumHeaderContent) {
        albumNameLabel.text = content.albumName
        artistNameLabel.text = content.artistName
        metaLabel.text = content.metadataText
        playButton.configuration?.title = content.playButtonTitle
        shuffleButton.configuration?.title = content.shuffleButtonTitle
        updateLayoutForSizeClass()
    }

    func setButtonsEnabled(_ enabled: Bool) {
        playButton.isEnabled = enabled
        shuffleButton.isEnabled = enabled
    }

    func prepareForReuse() {
        albumNameLabel.text = nil
        artistNameLabel.text = nil
        metaLabel.text = nil
        onPlayTapped = {}
        onShuffleTapped = {}
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.horizontalSizeClass != previousTraitCollection?.horizontalSizeClass {
            updateLayoutForSizeClass()
        }
    }

    @objc private func playButtonTapped() {
        onPlayTapped()
    }

    @objc private func shuffleButtonTapped() {
        onShuffleTapped()
    }

    private func setup() {
        shadowContainer.addSubview(artworkContainerView)

        infoStack.axis = .vertical
        infoStack.spacing = 4
        infoStack.alignment = .center
        infoStack.addArrangedSubview(albumNameLabel)
        infoStack.addArrangedSubview(artistNameLabel)
        infoStack.addArrangedSubview(metaLabel)

        buttonStack.axis = .horizontal
        buttonStack.spacing = 8
        buttonStack.addArrangedSubview(playButton)
        buttonStack.addArrangedSubview(shuffleButton)
        infoStack.addArrangedSubview(buttonStack)
        infoStack.setCustomSpacing(InterfaceStyle.Spacing.small, after: metaLabel)

        contentStack.axis = .vertical
        contentStack.spacing = InterfaceStyle.Spacing.medium
        contentStack.alignment = .center
        contentStack.addArrangedSubview(shadowContainer)
        contentStack.addArrangedSubview(infoStack)

        addSubview(contentStack)

        artworkContainerView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        shadowContainer.snp.makeConstraints { make in
            make.size.equalTo(220)
        }
        contentStack.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(InterfaceStyle.Spacing.medium)
            make.leading.equalToSuperview().offset(InterfaceStyle.Spacing.medium)
            make.trailing.equalToSuperview().offset(-InterfaceStyle.Spacing.medium)
            make.bottom.equalToSuperview().offset(-InterfaceStyle.Spacing.small)
        }

        playButton.addTarget(self, action: #selector(playButtonTapped), for: .touchUpInside)
        shuffleButton.addTarget(self, action: #selector(shuffleButtonTapped), for: .touchUpInside)
        updateLayoutForSizeClass()
    }

    private func updateLayoutForSizeClass() {
        let isRegular = traitCollection.horizontalSizeClass == .regular

        if isRegular {
            contentStack.axis = .horizontal
            contentStack.alignment = .center
            contentStack.spacing = InterfaceStyle.Spacing.large
            infoStack.alignment = .leading
            albumNameLabel.textAlignment = .natural
            artistNameLabel.textAlignment = .natural
            metaLabel.textAlignment = .natural
            applyButtonStyle(to: playButton, filled: true)
            applyButtonStyle(to: shuffleButton, filled: false)
        } else {
            contentStack.axis = .vertical
            contentStack.alignment = .center
            contentStack.spacing = InterfaceStyle.Spacing.medium
            infoStack.alignment = .center
            albumNameLabel.textAlignment = .center
            artistNameLabel.textAlignment = .center
            metaLabel.textAlignment = .center
            applyButtonStyle(to: playButton, filled: false)
            applyButtonStyle(to: shuffleButton, filled: false)
        }
    }

    private func applyButtonStyle(to button: UIButton, filled: Bool) {
        guard let config = button.configuration else { return }
        let title = config.title
        let image = config.image
        if filled {
            var newConfig = UIButton.Configuration.filled()
            newConfig.title = title
            newConfig.image = image
            newConfig.imagePadding = 4
            newConfig.cornerStyle = .capsule
            newConfig.buttonSize = .medium
            newConfig.baseBackgroundColor = .tintColor
            newConfig.baseForegroundColor = .white
            newConfig.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
                pointSize: 13,
                weight: .semibold,
            )
            newConfig.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attrs in
                var attrs = attrs
                attrs.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
                return attrs
            }
            button.configuration = newConfig
        } else {
            var newConfig = UIButton.Configuration.gray()
            newConfig.title = title
            newConfig.image = image
            newConfig.imagePadding = 4
            newConfig.cornerStyle = .capsule
            newConfig.buttonSize = .medium
            newConfig.baseBackgroundColor = UIColor.systemGray5
            newConfig.baseForegroundColor = .tintColor
            newConfig.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
                pointSize: 13,
                weight: .semibold,
            )
            newConfig.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attrs in
                var attrs = attrs
                attrs.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
                return attrs
            }
            button.configuration = newConfig
        }
    }

    private func makeActionButton(systemImage: String) -> UIButton {
        let button = UIButton(type: .system)
        var config = UIButton.Configuration.gray()
        config.image = UIImage(systemName: systemImage)
        config.imagePadding = 4
        config.cornerStyle = .capsule
        config.buttonSize = .medium
        config.baseBackgroundColor = UIColor.systemGray5
        config.baseForegroundColor = .tintColor
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
            pointSize: 13,
            weight: .semibold,
        )
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attrs in
            var attrs = attrs
            attrs.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
            return attrs
        }
        button.configuration = config
        return button
    }
}
