import SnapKit
import UIKit

extension NowPlayingTransportView {
    func setupViewHierarchy() {
        addSubview(titleView)
        addSubview(titleJumpButton)

        progressColumn.addArrangedSubview(progressTrackView)
        progressColumn.addArrangedSubview(playbackTimeRowView)
        addSubview(progressColumn)

        favoriteButtonContainer.addSubview(favoriteButton)
        transportStack.addArrangedSubview(favoriteButtonContainer)
        transportStack.addArrangedSubview(previousButton)
        transportStack.addArrangedSubview(playPauseButton)
        transportStack.addArrangedSubview(nextButton)
        transportStack.addArrangedSubview(routePickerContainer)
        addSubview(transportStack)
    }

    func setupLayout() {
        titleView.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(Layout.verticalInset).priority(NowPlayingArtworkLayout.contentPriority)
            make.leading.trailing.equalToSuperview().priority(.high)
        }

        titleJumpButton.snp.makeConstraints { make in
            make.edges.equalTo(titleView)
        }

        progressTrackView.snp.makeConstraints { make in
            make.height.equalTo(8)
        }

        progressColumn.snp.makeConstraints { make in
            make.top.equalTo(titleView.snp.bottom).offset(Layout.titleToProgressSpacing).priority(NowPlayingArtworkLayout.contentPriority)
            make.leading.trailing.equalToSuperview().priority(.high)
        }

        previousButton.snp.makeConstraints { make in
            make.height.equalTo(Layout.buttonSize)
        }
        playPauseButton.snp.makeConstraints { make in
            make.height.equalTo(Layout.buttonSize)
        }
        nextButton.snp.makeConstraints { make in
            make.height.equalTo(Layout.buttonSize)
        }

        transportStack.snp.makeConstraints { make in
            make.top.equalTo(progressColumn.snp.bottom).offset(Layout.verticalContentSpacing).priority(NowPlayingArtworkLayout.contentPriority)
            make.leading.trailing.equalToSuperview().priority(.high)
            make.height.equalTo(Layout.buttonSize).priority(NowPlayingArtworkLayout.contentPriority)
            transportBottomConstraint = make.bottom.equalToSuperview()
                .offset(-Layout.verticalInset)
                .priority(NowPlayingArtworkLayout.contentPriority)
                .constraint
        }

        favoriteButton.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        routePickerContainer.snp.makeConstraints { make in
            make.height.equalTo(Layout.buttonSize)
        }
    }

    func makeIconButton(
        systemName: String,
        pointSize: CGFloat,
        weight: UIImage.SymbolWeight,
        accessibilityLabel: String,
    ) -> UIButton {
        let button = UIButton(type: .system)
        var configuration = UIButton.Configuration.plain()
        configuration.baseForegroundColor = Palette.primaryText
        configuration.contentInsets = .zero
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
            pointSize: pointSize,
            weight: weight,
        )
        button.configuration = configuration
        button.tintColor = Palette.primaryText
        button.setImage(UIImage(systemName: systemName), for: .normal)
        button.accessibilityLabel = accessibilityLabel
        return button
    }
}
