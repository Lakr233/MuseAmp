import Combine
import SnapKit
import UIKit

@MainActor
final class NowPlayingPlaybackTimeRowView: UIView {
    private let playbackController: PlaybackController
    private var cancellables: Set<AnyCancellable> = []
    private var latestDuration: TimeInterval = 0

    private let timeRow: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.distribution = .equalSpacing
        stackView.spacing = 0
        return stackView
    }()

    private let elapsedLabel: UILabel = {
        let label = UILabel()
        label.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        label.textColor = NowPlayingTransportView.Palette.secondaryText
        label.textAlignment = .right
        return label
    }()

    private let remainingLabel: UILabel = {
        let label = UILabel()
        label.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        label.textColor = NowPlayingTransportView.Palette.secondaryText
        label.textAlignment = .left
        return label
    }()

    init(playbackController: PlaybackController) {
        self.playbackController = playbackController
        super.init(frame: .zero)
        timeRow.addArrangedSubview(elapsedLabel)
        timeRow.addArrangedSubview(remainingLabel)
        for label in [elapsedLabel, remainingLabel] {
            label.setContentCompressionResistancePriority(NowPlayingArtworkLayout.contentPriority, for: .vertical)
        }
        addSubview(timeRow)
        timeRow.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        bindDataSource()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    private func bindDataSource() {
        playbackController.$snapshot
            .map(\.duration)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] duration in
                self?.latestDuration = duration
            }
            .store(in: &cancellables)

        playbackController.playbackTimeSubject
            .map { ($0.currentTime, $0.duration) }
            .prepend((playbackController.snapshot.currentTime, playbackController.snapshot.duration))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] currentTime, duration in
                guard let self else { return }
                let effectiveDuration = max(duration, latestDuration)
                elapsedLabel.text = formattedPlaybackTime(currentTime)
                remainingLabel.text = "-\(formattedPlaybackTime(max(effectiveDuration - currentTime, 0)))"
            }
            .store(in: &cancellables)
    }
}
