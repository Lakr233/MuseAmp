import Combine
import UIKit

@MainActor
final class ProgressTrackView: UIView {
    private static let scrubCommitCooldown: TimeInterval = 0.5

    private let trackColor = UIColor(white: 1.0, alpha: 0.1)
    private let fillColor = UIColor(white: 1.0, alpha: 1.0)

    private(set) var isScrubbing = false

    var progress: CGFloat = 0 {
        didSet {
            guard !isScrubbing else { return }
            scrubbingProgress = progress
            updateFillLayout()
        }
    }

    private let playbackController: PlaybackController
    private var cancellables: Set<AnyCancellable> = []
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .soft)
    private let fillView: UIView
    private var currentTrackID = ""
    private var currentDuration: TimeInterval = 0
    private var appliedProgress: CGFloat = 0
    private var scrubbingProgress: CGFloat = 0
    private var scrubCommitCooldownDeadline: Date = .distantPast
    private lazy var panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))

    init(playbackController: PlaybackController) {
        self.playbackController = playbackController
        fillView = UIView()
        fillView.clipsToBounds = true
        fillView.layer.cornerCurve = .continuous
        fillView.layer.cornerRadius = 4
        super.init(frame: .zero)
        clipsToBounds = true
        layer.cornerCurve = .continuous
        layer.cornerRadius = 4
        backgroundColor = trackColor
        fillView.backgroundColor = fillColor
        addSubview(fillView)
        addGestureRecognizer(panGesture)
        bindDataSource()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func point(inside point: CGPoint, with _: UIEvent?) -> Bool {
        let expandedBounds = bounds.insetBy(dx: -16, dy: -16)
        return expandedBounds.contains(point)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        fillView.frame = CGRect(x: 0, y: 0, width: bounds.width * scrubbingProgress, height: bounds.height)
    }

    func cancelScrubbing() {
        guard isScrubbing else { return }
        isScrubbing = false
        scrubbingProgress = appliedProgress
        updateFillLayout()
    }

    private func applyPlaybackState(trackID: String, currentTime: TimeInterval, duration: TimeInterval) {
        let trackDidChange = currentTrackID != trackID
        let progressValue: CGFloat = if duration > 0 {
            CGFloat(min(max(currentTime / duration, 0), 1))
        } else {
            0
        }

        if trackDidChange {
            isScrubbing = false
        }

        // Date's >= and <= are back-deployed in the iOS 27.2 SDK and resolve to a
        // missing symbol on iOS 27.2 betas; compare the interval instead.
        if scrubCommitCooldownDeadline.timeIntervalSinceNow <= 0 || trackDidChange {
            appliedProgress = progressValue
            progress = progressValue
        }

        currentTrackID = trackID
        currentDuration = duration
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let p = progress(for: gesture) else {
            return
        }

        switch gesture.state {
        case .began:
            isScrubbing = true
            scrubbingProgress = progress
            updateFillLayout()
            feedbackGenerator.prepare()
            feedbackGenerator.impactOccurred(intensity: 0.8)
        case .changed:
            updateScrubbingProgress(p)
        case .ended:
            isScrubbing = false
            updateScrubbingProgress(p)
            feedbackGenerator.impactOccurred(intensity: 0.55)
            scrubCommitCooldownDeadline = Date().addingTimeInterval(Self.scrubCommitCooldown)
            guard currentDuration > 0 else {
                return
            }
            playbackController.seek(to: currentDuration * scrubbingProgress)
        case .cancelled, .failed:
            isScrubbing = false
            scrubbingProgress = appliedProgress
            updateFillLayout()
        default:
            break
        }
    }

    private func updateScrubbingProgress(_ p: CGFloat) {
        let clamped = min(max(p, 0), 1)
        scrubbingProgress = clamped
        updateFillLayout()
    }

    private func progress(for gesture: UIGestureRecognizer) -> CGFloat? {
        guard bounds.width > 0 else { return nil }
        let location = gesture.location(in: self)
        return min(max(location.x / bounds.width, 0), 1)
    }

    private func bindDataSource() {
        let timeSource = playbackController.playbackTimeSubject
            .map { ($0.currentTime, $0.duration) }
            .prepend((playbackController.snapshot.currentTime, playbackController.snapshot.duration))

        Publishers.CombineLatest(playbackController.$snapshot, timeSource)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot, time in
                self?.applyPlaybackState(
                    trackID: snapshot.currentTrack?.id ?? "",
                    currentTime: time.0,
                    duration: max(time.1, snapshot.duration),
                )
            }
            .store(in: &cancellables)
    }

    private func updateFillLayout() {
        setNeedsLayout()
        Interface.quickAnimate { self.layoutIfNeeded() }
    }
}
