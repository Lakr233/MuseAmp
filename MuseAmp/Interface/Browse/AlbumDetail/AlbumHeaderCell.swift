//
//  AlbumHeaderCell.swift
//  MuseAmp
//
//  Created by @Lakr233 on 2026/04/11.
//

import SnapKit
import SubsonicClientKit
import UIKit

final class AlbumHeaderCell: TableBaseCell {
    static let reuseID = "AlbumHeaderCell"

    let artworkImageView = MuseAmpImageView()
    private let headerView = AlbumHeaderView()

    var onPlayTapped: () -> Void {
        get { headerView.onPlayTapped }
        set { headerView.onPlayTapped = newValue }
    }

    var onShuffleTapped: () -> Void {
        get { headerView.onShuffleTapped }
        set { headerView.onShuffleTapped = newValue }
    }

    var onArtistTapped: () -> Void {
        get { headerView.onArtistTapped }
        set { headerView.onArtistTapped = newValue }
    }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        artworkImageView.configure(placeholder: "square.stack.fill", cornerRadius: 12)
        artworkImageView.allowsPreviewOnTap = true
        contentView.addSubview(headerView)
        headerView.artworkContainerView.addSubview(artworkImageView)

        headerView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        artworkImageView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    func configure(album: CatalogAlbum, artworkURL: URL?) {
        var meta: [String] = []
        if let genres = album.attributes.genreNames, let first = genres.first { meta.append(first) }
        if let date = album.attributes.releaseDate { meta.append(String(date.prefix(4))) }
        headerView.configure(content: AlbumHeaderContent(
            albumName: album.attributes.name,
            artistName: album.attributes.artistName,
            metadataText: meta.joined(separator: " \u{00B7} "),
            playButtonTitle: String(localized: "Play"),
            shuffleButtonTitle: String(localized: "Shuffle"),
        ))
        artworkImageView.loadImage(url: artworkURL)
    }

    func setButtonsEnabled(_ enabled: Bool) {
        headerView.setButtonsEnabled(enabled)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        headerView.prepareForReuse()
        artworkImageView.reset()
    }
}
