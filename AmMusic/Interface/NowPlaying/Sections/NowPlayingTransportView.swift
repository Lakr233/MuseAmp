import AVKit
import GlyphixTextFx
import SnapKit
import Then
import UIKit

final class NowPlayingTransportView: UIView {
    private enum Layout {
        static let horizontalInset: CGFloat = 20
        static let verticalInset: CGFloat = 12
        static let verticalContentSpacing: CGFloat = 12
        static let progressSpacing: CGFloat = 10
        static let transportSpacing: CGFloat = 12
        static let buttonSize: CGFloat = 44
        static let favoriteSymbolPointSize: CGFloat = 16
        static let unavailableTransportButtonAlpha: CGFloat = 0.1
        static let scrubbingTrackScaleY: CGFloat = 1.35
        static let scrubbingLabelScale: CGFloat = 1.04
        static let scrubbingPlayPauseScale: CGFloat = 0.92
    }

    private enum Palette {
        static let primaryText = UIColor.white
        static let subtitleText = UIColor.white
        static let secondaryText = UIColor.white.withAlphaComponent(0.76)
        static let progressTrack = UIColor.white.withAlphaComponent(0.2)
        static let progressFill = UIColor.white
    }

    private let titleStack = UIStackView().then {
        $0.axis = .vertical
        $0.alignment = .fill
        $0.spacing = Layout.verticalContentSpacing
    }

    private let titleJumpButton = UIButton(type: .system).then {
        $0.backgroundColor = .clear
        $0.tintColor = .clear
        $0.accessibilityLabel = String(localized: "Open Lyrics")
        $0.accessibilityHint = String(localized: "Switches to the lyrics view")
    }

    private let titleLabel = GlyphixTextLabel().then {
        $0.font = UIFontMetrics(forTextStyle: .title3).scaledFont(
            for: .systemFont(ofSize: 20, weight: .semibold)
        )
        $0.textColor = Palette.primaryText
        $0.textAlignment = .center
        $0.numberOfLines = 0
        $0.lineBreakMode = .byWordWrapping
        $0.isBlurEffectEnabled = false
        $0.isSmoothRenderingEnabled = false
        $0.countsDown = true
        $0.clipsToBounds = false
    }

    private let artistLabel = GlyphixTextLabel().then {
        $0.font = UIFontMetrics(forTextStyle: .footnote).scaledFont(
            for: .systemFont(ofSize: 13, weight: .regular)
        )
        $0.textColor = Palette.subtitleText
        $0.textAlignment = .center
        $0.numberOfLines = 0
        $0.lineBreakMode = .byWordWrapping
        $0.isBlurEffectEnabled = false
        $0.isSmoothRenderingEnabled = false
        $0.countsDown = true
        $0.clipsToBounds = false
    }

    private let progressRow = UIStackView().then {
        $0.axis = .horizontal
        $0.alignment = .center
        $0.spacing = Layout.progressSpacing
    }

    private let elapsedLabel = UILabel().then {
        $0.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(
            for: .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        )
        $0.textColor = Palette.secondaryText
        $0.textAlignment = .center
        $0.adjustsFontForContentSizeCategory = true
    }

    private let remainingLabel = UILabel().then {
        $0.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(
            for: .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        )
        $0.textColor = Palette.secondaryText
        $0.textAlignment = .center
        $0.adjustsFontForContentSizeCategory = true
    }

    private let progressTrackView = UIView().then {
        $0.backgroundColor = Palette.progressTrack
        $0.clipsToBounds = true
        $0.layer.cornerCurve = .continuous
        $0.layer.cornerRadius = 4
    }

    private let progressFillView = UIView().then {
        $0.backgroundColor = Palette.progressFill
        $0.clipsToBounds = true
        $0.layer.cornerCurve = .continuous
        $0.layer.cornerRadius = 4
    }

    private let currentLyricLabel = GlyphixTextLabel().then {
        $0.font = UIFontMetrics(forTextStyle: .footnote).scaledFont(
            for: .systemFont(ofSize: 13, weight: .medium)
        )
        $0.textColor = Palette.primaryText
        $0.textAlignment = .center
        $0.numberOfLines = 1
        $0.lineBreakMode = .byTruncatingTail
        $0.isBlurEffectEnabled = false
        $0.isSmoothRenderingEnabled = false
        $0.countsDown = true
        $0.clipsToBounds = false
        $0.isHidden = true
    }

    private let transportStack = UIStackView().then {
        $0.axis = .horizontal
        $0.alignment = .center
        $0.distribution = .fillEqually
        $0.spacing = Layout.transportSpacing
    }

    private lazy var favoriteButton = makeIconButton(
        systemName: "heart",
        pointSize: Layout.favoriteSymbolPointSize,
        weight: .regular,
        accessibilityLabel: String(localized: "Favorite")
    )

    private let favoriteButtonContainer = UIView()

    private lazy var previousButton = makeIconButton(
        systemName: "backward.fill",
        pointSize: 20,
        weight: .regular,
        accessibilityLabel: String(localized: "Previous")
    )

    private lazy var playPauseButton = makeIconButton(
        systemName: "pause.fill",
        pointSize: 24,
        weight: .regular,
        accessibilityLabel: String(localized: "Play Pause")
    )

    private lazy var nextButton = makeIconButton(
        systemName: "forward.fill",
        pointSize: 20,
        weight: .regular,
        accessibilityLabel: String(localized: "Next")
    )

    private let routePickerContainer = UIView().then {
        $0.layer.cornerCurve = .continuous
        $0.layer.cornerRadius = Layout.buttonSize / 2
    }

    private weak var viewModel: NowPlayingControlIslandViewModel?
    private var progressWidthConstraint: Constraint?
    private var currentProgress: CGFloat = 0
    private var currentTime: TimeInterval = 0
    private var currentDuration: TimeInterval = 0
    private var currentTitleText: String?
    private var currentArtistText: String?
    private var currentFavoriteState = false
    private var currentPlaybackState = true
    private var currentRouteName: String?
    private weak var installedRoutePickerView: AVRoutePickerView?
    private var isScrubbing = false
    private var scrubbingProgress: CGFloat = 0
    private let buttonFeedbackGenerator = UIImpactFeedbackGenerator(style: .light)
    private var scrubbingFeedbackGenerator = UIImpactFeedbackGenerator(style: .soft)
    private lazy var progressPanGesture = UIPanGestureRecognizer(target: self, action: #selector(handleProgressPan(_:)))
    private lazy var progressTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleProgressTap(_:)))

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        setupViewHierarchy()
        setupLayout()
        configureButtons()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateProgressWidth()
    }

    func setAnimationsSuspended(_ suspended: Bool) {
        titleLabel.disablesAnimations = suspended
        artistLabel.disablesAnimations = suspended
        currentLyricLabel.disablesAnimations = suspended

        if isScrubbing {
            endScrubbingInteraction(commit: false)
        }

        guard suspended else {
            return
        }

        removeAnimationsRecursively()
    }

    func bind(to viewModel: NowPlayingControlIslandViewModel) {
        self.viewModel = viewModel
        configure(with: viewModel.content, animated: false)
    }

    func configure(
        with content: NowPlayingControlIslandViewModel.Content,
        animated: Bool = false
    ) {
        let layoutAnimationView = layoutAnimationContainerView()
        let shouldAnimateProgressChange = shouldAnimateProgressChange(
            to: content,
            requestedAnimation: animated
        )

        let updates = { [self] in
            if currentTitleText != content.title {
                currentTitleText = content.title
                titleLabel.text = content.title
            }
            if currentArtistText != content.artist {
                currentArtistText = content.artist
                artistLabel.text = content.artist
            }
            applyPlaybackProgress(content, animated: shouldAnimateProgressChange)
            if currentFavoriteState != content.isFavorite {
                currentFavoriteState = content.isFavorite
                favoriteButton.setImage(
                    UIImage(
                        systemName: content.isFavorite ? "heart.fill" : "heart",
                        withConfiguration: UIImage.SymbolConfiguration(
                            pointSize: Layout.favoriteSymbolPointSize,
                            weight: .regular
                        )
                    ),
                    for: .normal
                )
            }
            if currentPlaybackState != content.isPlaying {
                currentPlaybackState = content.isPlaying
                playPauseButton.setImage(
                    UIImage(
                        systemName: content.isPlaying ? "pause.fill" : "play.fill",
                        withConfiguration: UIImage.SymbolConfiguration(pointSize: 24, weight: .regular)
                    ),
                    for: .normal
                )
            }
            favoriteButton.isEnabled = content.hasActiveTrack
            favoriteButton.alpha = content.hasActiveTrack ? 1 : Layout.unavailableTransportButtonAlpha
            previousButton.isEnabled = content.hasActiveTrack && content.isPreviousAvailable
            previousButton.alpha = previousButton.isEnabled ? 1 : Layout.unavailableTransportButtonAlpha
            playPauseButton.isEnabled = content.hasActiveTrack
            playPauseButton.alpha = content.hasActiveTrack ? 1 : Layout.unavailableTransportButtonAlpha
            nextButton.isEnabled = content.hasActiveTrack
            nextButton.alpha = content.hasActiveTrack ? 1 : Layout.unavailableTransportButtonAlpha
            routePickerContainer.isUserInteractionEnabled = content.hasActiveTrack
            routePickerContainer.alpha = content.hasActiveTrack ? 1 : Layout.unavailableTransportButtonAlpha
            installedRoutePickerView?.isUserInteractionEnabled = content.hasActiveTrack
            installedRoutePickerView?.accessibilityLabel = String(localized: "Audio Route")
            if currentRouteName != content.routeName {
                currentRouteName = content.routeName
                installedRoutePickerView?.accessibilityValue = content.routeName
            }
        }

        guard animated else {
            updates()
            layoutAnimationView.layoutIfNeeded()
            return
        }

        InterfaceAnimation.springAnimate(
            duration: 0.42,
            dampingRatio: 0.9,
            initialVelocity: 1
        ) {
            updates()
            layoutAnimationView.layoutIfNeeded()
        }
    }

    func updateCurrentLyricLine(_ line: String?) {
        let hasLine = line != nil && !line!.isEmpty
        currentLyricLabel.text = line
        currentLyricLabel.isHidden = !hasLine
        InterfaceAnimation.smoothSpringAnimate {
            self.layoutAnimationContainerView().layoutIfNeeded()
        }
    }

    func installRoutePickerView(_ routePickerView: AVRoutePickerView) {
        installedRoutePickerView = routePickerView
        routePickerContainer.subviews.forEach { $0.removeFromSuperview() }
        routePickerContainer.addSubview(routePickerView)
        routePickerView.tintColor = Palette.primaryText
        routePickerView.activeTintColor = Palette.primaryText
        routePickerView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    private func setupViewHierarchy() {
        titleStack.addArrangedSubview(titleLabel)
        titleStack.addArrangedSubview(artistLabel)
        addSubview(titleStack)
        addSubview(titleJumpButton)

        progressTrackView.addSubview(progressFillView)
        progressRow.addArrangedSubview(elapsedLabel)
        progressRow.addArrangedSubview(progressTrackView)
        progressRow.addArrangedSubview(remainingLabel)
        addSubview(progressRow)
        addSubview(currentLyricLabel)

        favoriteButtonContainer.addSubview(favoriteButton)
        transportStack.addArrangedSubview(favoriteButtonContainer)
        transportStack.addArrangedSubview(previousButton)
        transportStack.addArrangedSubview(playPauseButton)
        transportStack.addArrangedSubview(nextButton)
        transportStack.addArrangedSubview(routePickerContainer)
        addSubview(transportStack)
    }

    private func setupLayout() {
        titleStack.snp.makeConstraints { make in
            make.top.equalToSuperview().inset(Layout.verticalInset).priority(.high)
            make.leading.trailing.equalToSuperview().inset(Layout.horizontalInset).priority(.high)
        }

        titleJumpButton.snp.makeConstraints { make in
            make.top.bottom.equalTo(titleStack)
            make.leading.equalTo(titleStack.snp.leading)
            make.trailing.equalTo(titleStack.snp.trailing)
        }

        elapsedLabel.snp.makeConstraints { make in
            make.width.greaterThanOrEqualTo(30)
        }

        remainingLabel.snp.makeConstraints { make in
            make.width.greaterThanOrEqualTo(38)
        }

        progressTrackView.snp.makeConstraints { make in
            make.height.equalTo(8).priority(.high)
        }

        progressFillView.snp.makeConstraints { make in
            make.leading.top.bottom.equalToSuperview()
            progressWidthConstraint = make.width.equalTo(0).constraint
        }

        progressRow.snp.makeConstraints { make in
            make.top.equalTo(titleStack.snp.bottom).offset(Layout.verticalContentSpacing).priority(.high)
            make.leading.trailing.equalToSuperview().inset(Layout.horizontalInset).priority(.high)
            make.height.equalTo(14).priority(.high)
        }

        favoriteButton.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        for button in [previousButton, playPauseButton, nextButton] {
            button.snp.makeConstraints { make in
                make.height.equalTo(Layout.buttonSize).priority(.high)
            }
        }

        routePickerContainer.snp.makeConstraints { make in
            make.height.equalTo(Layout.buttonSize).priority(.high)
        }

        transportStack.snp.makeConstraints { make in
            make.top.equalTo(progressRow.snp.bottom).offset(Layout.verticalContentSpacing).priority(.high)
            make.leading.trailing.equalToSuperview().inset(Layout.horizontalInset).priority(.high)
            make.height.equalTo(Layout.buttonSize).priority(.high)
        }

        currentLyricLabel.snp.makeConstraints { make in
            make.top.equalTo(transportStack.snp.bottom).offset(NowPlayingArtworkLayout.contentSpacing).priority(.high)
            make.leading.trailing.equalToSuperview().inset(Layout.horizontalInset).priority(.high)
            make.bottom.equalToSuperview().inset(Layout.verticalInset).priority(.high)
        }
    }

    private func configureButtons() {
        titleJumpButton.addTarget(self, action: #selector(titleJumpTapped), for: .touchUpInside)
        favoriteButton.addTarget(self, action: #selector(favoriteTapped), for: .touchUpInside)
        previousButton.addTarget(self, action: #selector(previousTapped), for: .touchUpInside)
        playPauseButton.addTarget(self, action: #selector(playPauseTapped), for: .touchUpInside)
        nextButton.addTarget(self, action: #selector(nextTapped), for: .touchUpInside)
        progressRow.addGestureRecognizer(progressTapGesture)
        progressRow.addGestureRecognizer(progressPanGesture)
    }

    private func applyPlaybackProgress(
        _ content: NowPlayingControlIslandViewModel.Content,
        animated: Bool
    ) {
        currentTime = content.currentTime
        currentDuration = content.duration

        guard !isScrubbing else {
            return
        }

        let updates = {
            self.elapsedLabel.text = content.elapsedText
            self.remainingLabel.text = content.remainingText
            self.currentProgress = min(max(content.progress, 0), 1)
            self.setNeedsLayout()
            self.layoutIfNeeded()
        }

        guard animated else {
            updates()
            return
        }

        InterfaceAnimation.springAnimate(
            duration: 0.32,
            dampingRatio: 0.92,
            initialVelocity: 0.9,
            animations: updates
        )
    }

    private func shouldAnimateProgressChange(
        to content: NowPlayingControlIslandViewModel.Content,
        requestedAnimation: Bool
    ) -> Bool {
        guard !requestedAnimation, !isScrubbing, currentDuration > 0 else {
            return false
        }

        let timeDelta = abs(content.currentTime - currentTime)
        let progressDelta = abs(content.progress - currentProgress)
        return timeDelta > 1 || progressDelta > 0.05
    }

    private func updateProgressWidth() {
        let progress = isScrubbing ? scrubbingProgress : currentProgress
        let width = progressTrackView.bounds.width * progress
        progressWidthConstraint?.update(offset: width)
    }

    private func layoutAnimationContainerView() -> UIView {
        var responder: UIResponder? = self

        while let currentResponder = responder {
            if let viewController = currentResponder as? UIViewController {
                return viewController.view
            }
            responder = currentResponder.next
        }

        return self
    }

    private func updateScrubbingState(for progress: CGFloat) {
        let clampedProgress = min(max(progress, 0), 1)
        scrubbingProgress = clampedProgress
        let scrubbedTime = currentDuration * clampedProgress
        let remainingTime = max(currentDuration - scrubbedTime, 0)
        elapsedLabel.text = formattedPlaybackTime(scrubbedTime)
        remainingLabel.text = "-\(formattedPlaybackTime(remainingTime))"
        setNeedsLayout()
        layoutIfNeeded()
    }

    private func beginScrubbingInteraction() {
        guard currentDuration > 0 else {
            return
        }

        isScrubbing = true
        scrubbingProgress = currentProgress
        scrubbingFeedbackGenerator.prepare()
        scrubbingFeedbackGenerator.impactOccurred(intensity: 0.8)

        InterfaceAnimation.quickAnimate(duration: 0.18) {
            self.progressTrackView.transform = CGAffineTransform(scaleX: 1, y: Layout.scrubbingTrackScaleY)
            self.progressFillView.transform = CGAffineTransform(scaleX: 1, y: Layout.scrubbingTrackScaleY)
            self.elapsedLabel.transform = CGAffineTransform(scaleX: Layout.scrubbingLabelScale, y: Layout.scrubbingLabelScale)
            self.remainingLabel.transform = CGAffineTransform(scaleX: Layout.scrubbingLabelScale, y: Layout.scrubbingLabelScale)
            self.playPauseButton.transform = CGAffineTransform(
                scaleX: Layout.scrubbingPlayPauseScale,
                y: Layout.scrubbingPlayPauseScale
            )
        }
    }

    private func endScrubbingInteraction(commit: Bool) {
        guard isScrubbing else {
            return
        }

        let scrubbedTime = currentDuration * scrubbingProgress
        isScrubbing = false
        currentProgress = scrubbingProgress

        InterfaceAnimation.quickAnimate {
            self.progressTrackView.transform = .identity
            self.progressFillView.transform = .identity
            self.elapsedLabel.transform = .identity
            self.remainingLabel.transform = .identity
            self.playPauseButton.transform = .identity
        }

        if commit {
            scrubbingFeedbackGenerator.impactOccurred(intensity: 0.55)
            viewModel?.seek(to: scrubbedTime)
        } else {
            elapsedLabel.text = formattedPlaybackTime(currentTime)
            remainingLabel.text = "-\(formattedPlaybackTime(max(currentDuration - currentTime, 0)))"
        }

        setNeedsLayout()
        layoutIfNeeded()
    }

    private func progress(for gesture: UIGestureRecognizer) -> CGFloat? {
        guard currentDuration > 0, progressTrackView.bounds.width > 0 else {
            return nil
        }

        let location = gesture.location(in: progressTrackView)
        return min(max(location.x / progressTrackView.bounds.width, 0), 1)
    }

    private func makeIconButton(
        systemName: String,
        pointSize: CGFloat,
        weight: UIImage.SymbolWeight,
        accessibilityLabel: String
    ) -> UIButton {
        UIButton(type: .system).then {
            var configuration = UIButton.Configuration.plain()
            configuration.baseForegroundColor = Palette.primaryText
            configuration.contentInsets = .zero
            configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
                pointSize: pointSize,
                weight: weight
            )
            $0.configuration = configuration
            $0.tintColor = Palette.primaryText
            $0.setImage(UIImage(systemName: systemName), for: .normal)
            $0.accessibilityLabel = accessibilityLabel
        }
    }

    @objc
    private func titleJumpTapped() {
        buttonFeedbackGenerator.impactOccurred()
        viewModel?.setContentSelector(.lyrics)
    }

    @objc
    private func favoriteTapped() {
        buttonFeedbackGenerator.impactOccurred()
        viewModel?.favorite()
    }

    @objc
    private func previousTapped() {
        buttonFeedbackGenerator.impactOccurred()
        viewModel?.previous()
    }

    @objc
    private func playPauseTapped() {
        buttonFeedbackGenerator.impactOccurred()
        viewModel?.togglePlayPause()
    }

    @objc
    private func nextTapped() {
        buttonFeedbackGenerator.impactOccurred()
        viewModel?.next()
    }

    @objc
    private func handleProgressTap(_ gesture: UITapGestureRecognizer) {
        guard let progress = progress(for: gesture) else {
            return
        }

        beginScrubbingInteraction()
        updateScrubbingState(for: progress)
        endScrubbingInteraction(commit: true)
    }

    @objc
    private func handleProgressPan(_ gesture: UIPanGestureRecognizer) {
        guard let progress = progress(for: gesture) else {
            return
        }

        switch gesture.state {
        case .began:
            beginScrubbingInteraction()
            updateScrubbingState(for: progress)
        case .changed:
            if !isScrubbing {
                beginScrubbingInteraction()
            }
            updateScrubbingState(for: progress)
        case .ended, .cancelled, .failed:
            if isScrubbing {
                updateScrubbingState(for: progress)
                endScrubbingInteraction(commit: gesture.state == .ended)
            }
        default:
            break
        }
    }
}
