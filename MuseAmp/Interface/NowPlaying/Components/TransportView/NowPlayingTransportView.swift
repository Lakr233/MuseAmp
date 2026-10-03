import AVKit
import SnapKit
import UIKit

@MainActor
class NowPlayingTransportView: UIView {
    nonisolated enum Layout {
        static let horizontalInset: CGFloat = 20
        static let verticalInset: CGFloat = 12
        static let verticalContentSpacing: CGFloat = 12
        static let titleToProgressSpacing: CGFloat = 32
        static let progressSpacing: CGFloat = 10
        static let transportSpacing: CGFloat = 12
        static let buttonSize: CGFloat = 44
        static let unavailableTransportButtonAlpha: CGFloat = 0.1
    }

    nonisolated enum Palette {
        static let primaryText = UIColor.white
        static let subtitleText = UIColor.white
        static let secondaryText = UIColor.white.withAlphaComponent(0.76)
    }

    // MARK: - Subviews

    let titleView: NowPlayingTransportTitleView

    let titleJumpButton: UIButton = {
        let button = UIButton(type: .system)
        button.backgroundColor = .clear
        button.tintColor = .clear
        button.accessibilityLabel = String(localized: "Show in Album")
        button.accessibilityHint = String(localized: "Opens the album page for the current song")
        return button
    }()

    let progressColumn: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = Layout.progressSpacing
        return stackView
    }()

    let progressTrackView: ProgressTrackView
    let playbackTimeRowView: NowPlayingPlaybackTimeRowView

    let transportStack: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.distribution = .fillEqually
        stackView.spacing = Layout.transportSpacing
        return stackView
    }()

    lazy var favoriteButton = FavoritePlayerControlButton(playbackController: environment.playbackController)
    let favoriteButtonContainer = UIView()
    lazy var previousButton = PreviousPlayerControlButton(playbackController: environment.playbackController)
    lazy var playPauseButton = PlayPausePlayerControlButton(playbackController: environment.playbackController)
    lazy var nextButton = NextPlayerControlButton(playbackController: environment.playbackController)

    let routePickerContainer: NowPlayingRoutePickerContainerView

    // MARK: - State

    let environment: AppEnvironment
    var transportBottomConstraint: Constraint?

    // MARK: - Init

    init(environment: AppEnvironment) {
        self.environment = environment
        titleView = NowPlayingTransportTitleView(playbackController: environment.playbackController)
        progressTrackView = ProgressTrackView(playbackController: environment.playbackController)
        playbackTimeRowView = NowPlayingPlaybackTimeRowView(playbackController: environment.playbackController)
        routePickerContainer = NowPlayingRoutePickerContainerView(playbackController: environment.playbackController)
        super.init(frame: .zero)
        backgroundColor = .clear
        setupViewHierarchy()
        setupLayout()
        configureButtons()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    // MARK: - Public API

    func configureLabelStyle(titleFont: UIFont, artistFont: UIFont) {
        titleView.configureLabelStyle(titleFont: titleFont, artistFont: artistFont)
    }

    func setSongMenu(_ menu: UIMenu?) {
        titleJumpButton.menu = menu
    }

    func setAnimationsSuspended(_ suspended: Bool) {
        titleView.setAnimationsSuspended(suspended)

        if progressTrackView.isScrubbing {
            progressTrackView.cancelScrubbing()
            setNeedsLayout()
            layoutIfNeeded()
        }

        guard suspended else {
            return
        }

        ViewAnimationHelper.removeAnimationsRecursively(in: self)
    }

    func installRoutePickerView(_ routePickerView: AVRoutePickerView) {
        routePickerContainer.installRoutePickerView(routePickerView)
    }

    func detachAuxiliaryButtons() -> (favoriteContainer: UIView, routePickerContainer: UIView) {
        favoriteButtonContainer.removeFromSuperview()
        routePickerContainer.removeFromSuperview()
        return (favoriteButtonContainer, routePickerContainer)
    }

    func installSupplementaryView(
        _ view: UIView,
        spacing: CGFloat = NowPlayingArtworkLayout.contentSpacing,
    ) {
        transportBottomConstraint?.deactivate()
        addSubview(view)

        view.snp.makeConstraints { make in
            make.top.equalTo(transportStack.snp.bottom).offset(spacing).priority(NowPlayingArtworkLayout.contentPriority)
            make.leading.trailing.equalToSuperview().priority(.high)
            transportBottomConstraint = make.bottom.equalToSuperview()
                .offset(-Layout.verticalInset)
                .priority(NowPlayingArtworkLayout.contentPriority)
                .constraint
        }
    }

    private func configureButtons() {
        titleJumpButton.addTarget(self, action: #selector(titleJumpTapped), for: .touchUpInside)
    }
}
