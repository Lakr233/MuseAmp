//
//  TVNowPlayingContentView.swift
//  MuseAmpTV
//
//  Left-panel composition for the tvOS Now Playing page:
//  album artwork (top), title / subtitle, progress bar, and transport controls.
//

import SnapKit
import SwifterSwift
import Then
import UIKit

@MainActor
final class TVNowPlayingContentView: UIView {
    let albumImageView = TVMusicAlbumImageView()
    let titleView = TVMusicTitleView()
    let progressView = TVMusicProgressView()
    let transportBar = TVNowPlayingTransportBar()

    override init(frame: CGRect) {
        super.init(frame: frame)

        let stack = UIStackView().then {
            $0.axis = .vertical
            $0.spacing = TVNowPlayingLayout.spacing32
            $0.alignment = .fill
            $0.distribution = .equalSpacing
        }

        addSubview(stack)
        stack.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.left.right.equalToSuperview()
        }

        let transportContainer = UIView()
        transportContainer.addSubview(transportBar)
        transportBar.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.bottom.equalToSuperview()
        }

        let albumContainer = UIView()
        albumContainer.addSubview(albumImageView)
        albumImageView.snp.makeConstraints { make in
            make.center.equalToSuperview().priority(.required)
            make.left.right.equalToSuperview().priority(.low)
            make.top.bottom.equalToSuperview()
        }

        stack.addArrangedSubviews([
            UIView().then { $0.snp.makeConstraints { make in
                make.height.equalTo(128)
            }},
            albumContainer,
            titleView,
            progressView,
            transportContainer,
            UIView().then { $0.snp.makeConstraints { make in
                make.height.equalTo(128)
            }},
        ])
    }

    @available(*, unavailable)
    required init(coder _: NSCoder) {
        fatalError()
    }

    // MARK: - Public

    func configure(
        title: String,
        subtitle: String,
        artworkURL: URL?,
    ) {
        titleView.configure(title: title, subtitle: subtitle)
        albumImageView.configure(artworkURL: artworkURL)
    }
}
