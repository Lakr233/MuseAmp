//
//  AlbumHeaderCell.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import AmMusicKit
import SnapKit
import Then
import UIKit

final class AlbumHeaderCell: TableBaseCell {
    static let reuseID = "AlbumHeaderCell"

    let artworkImageView = AmImageView()

    private let shadowContainer = UIView().then {
        $0.layer.shadowColor = UIColor.black.cgColor
        $0.layer.shadowOpacity = 0.25
        $0.layer.shadowRadius = 8
        $0.layer.shadowOffset = CGSize(width: 0, height: 0)
    }

    private let albumNameLabel = CopyableLabel().then {
        $0.font = .systemFont(ofSize: 21, weight: .bold)
        $0.textAlignment = .center
        $0.numberOfLines = 0
    }

    private let artistNameLabel = CopyableLabel().then {
        $0.font = .systemFont(ofSize: 17, weight: .medium)
        $0.textColor = .tintColor
        $0.textAlignment = .center
    }

    private let metaLabel = CopyableLabel().then {
        $0.font = .preferredFont(forTextStyle: .caption1)
        $0.textColor = .secondaryLabel
        $0.textAlignment = .center
        $0.numberOfLines = 0
    }

    var onPlayTapped: () -> Void = {}
    var onShuffleTapped: () -> Void = {}

    private lazy var playButton = makeActionButton(
        title: String(localized: "Play"),
        systemImage: "play.fill",
    ).then {
        $0.addTarget(self, action: #selector(playButtonTapped), for: .touchUpInside)
    }

    private lazy var shuffleButton = makeActionButton(
        title: String(localized: "Shuffle"),
        systemImage: "shuffle",
    ).then {
        $0.addTarget(self, action: #selector(shuffleButtonTapped), for: .touchUpInside)
    }

    private let buttonStack = UIStackView().then {
        $0.axis = .horizontal
        $0.spacing = 8
    }

    private let infoStack = UIStackView()
    private let contentStack = UIStackView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        artworkImageView.configure(placeholder: "square.stack.fill", cornerRadius: 12)
        artworkImageView.allowsPreviewOnTap = true

        shadowContainer.addSubview(artworkImageView)
        artworkImageView.snp.makeConstraints { $0.edges.equalToSuperview() }

        // Info stack: text labels + buttons
        infoStack.axis = .vertical
        infoStack.spacing = 4
        infoStack.alignment = .center
        infoStack.addArrangedSubview(albumNameLabel)
        infoStack.addArrangedSubview(artistNameLabel)
        infoStack.addArrangedSubview(metaLabel)

        buttonStack.addArrangedSubview(playButton)
        buttonStack.addArrangedSubview(shuffleButton)
        infoStack.addArrangedSubview(buttonStack)
        infoStack.setCustomSpacing(InterfaceStyle.Spacing.small, after: metaLabel)

        // Content stack: artwork + info
        contentStack.axis = .vertical
        contentStack.spacing = InterfaceStyle.Spacing.medium
        contentStack.alignment = .center
        contentStack.addArrangedSubview(shadowContainer)
        contentStack.addArrangedSubview(infoStack)

        contentView.addSubview(contentStack)

        shadowContainer.snp.makeConstraints { make in
            make.size.equalTo(220).priority(.high)
        }

        contentStack.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(InterfaceStyle.Spacing.medium).priority(.high)
            make.leading.trailing.equalToSuperview().inset(InterfaceStyle.Spacing.medium).priority(.high)
            make.bottom.equalToSuperview().inset(InterfaceStyle.Spacing.small).priority(.high)
        }

        updateLayoutForSizeClass()
    }

    func configure(album: CatalogAlbum, artworkURL: URL?) {
        albumNameLabel.text = album.attributes.name
        artistNameLabel.text = album.attributes.artistName

        var meta: [String] = []
        if let genres = album.attributes.genreNames, let first = genres.first { meta.append(first) }
        if let date = album.attributes.releaseDate { meta.append(String(date.prefix(4))) }
        metaLabel.text = meta.joined(separator: " \u{00B7} ")

        artworkImageView.loadImage(url: artworkURL)
        updateLayoutForSizeClass()
    }

    // MARK: - Adaptive Layout

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
        } else {
            contentStack.axis = .vertical
            contentStack.alignment = .center
            contentStack.spacing = InterfaceStyle.Spacing.medium
            infoStack.alignment = .center
            albumNameLabel.textAlignment = .center
            artistNameLabel.textAlignment = .center
            metaLabel.textAlignment = .center
        }
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

    private func makeActionButton(title: String, systemImage: String) -> UIButton {
        UIButton(type: .system).then {
            var config = UIButton.Configuration.gray()
            config.title = title
            config.image = UIImage(systemName: systemImage)
            config.imagePadding = 4
            config.cornerStyle = .capsule
            config.buttonSize = .medium
            config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
                pointSize: 13, weight: .semibold,
            )
            config.titleTextAttributesTransformer = .init { attrs in
                var attrs = attrs
                attrs.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
                return attrs
            }
            config.baseForegroundColor = .tintColor
            $0.configuration = config
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        artworkImageView.reset()
        albumNameLabel.text = nil
        artistNameLabel.text = nil
        metaLabel.text = nil
        onPlayTapped = {}
        onShuffleTapped = {}
    }
}
