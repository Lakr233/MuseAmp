import Combine
import ConfigurableKit
import SnapKit
import UIKit

@MainActor
final class NowPlayingTransportTitleView: UIView {
    private let playbackController: PlaybackController
    private var cancellables: Set<AnyCancellable> = []

    private let titleStack: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = 4
        return stackView
    }()

    private let titleLabel: AnimatedTextLabel = {
        let label = AnimatedTextLabel()
        label.font = UIFontMetrics(forTextStyle: .title3).scaledFont(
            for: .systemFont(ofSize: 24, weight: .semibold),
        )
        label.textColor = NowPlayingTransportView.Palette.primaryText
        label.textAlignment = .center
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.clipsToBounds = false
        return label
    }()

    private let artistLabel: AnimatedTextLabel = {
        let label = AnimatedTextLabel()
        label.font = UIFontMetrics(forTextStyle: .footnote).scaledFont(
            for: .systemFont(ofSize: 14, weight: .regular),
        )
        label.textColor = NowPlayingTransportView.Palette.subtitleText
        label.textAlignment = .center
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.clipsToBounds = false
        return label
    }()

    init(playbackController: PlaybackController) {
        self.playbackController = playbackController
        super.init(frame: .zero)
        addSubview(titleStack)
        titleStack.addArrangedSubview(titleLabel)
        titleStack.addArrangedSubview(artistLabel)
        titleStack.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        for label in [titleLabel, artistLabel] {
            label.setContentCompressionResistancePriority(NowPlayingArtworkLayout.contentPriority, for: .vertical)
        }
        bindDataSource()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    func configureLabelStyle(titleFont: UIFont, artistFont: UIFont) {
        titleLabel.font = titleFont
        artistLabel.font = artistFont
    }

    func setAnimationsSuspended(_ suspended: Bool) {
        titleLabel.disablesAnimations = suspended
        artistLabel.disablesAnimations = suspended
    }

    private func bindDataSource() {
        let cleanTitlePreference = ConfigurableKit
            .publisher(forKey: AppPreferences.cleanSongTitleKey, type: Bool.self)
            .map { $0 ?? AppPreferences.isCleanSongTitleEnabled }
            .prepend(AppPreferences.isCleanSongTitleEnabled)

        Publishers.CombineLatest(playbackController.$snapshot, cleanTitlePreference)
            .map { snapshot, cleanTitleEnabled in
                NowPlayingContentMapper.makeContent(
                    from: snapshot,
                    cleanTitleEnabled: cleanTitleEnabled,
                )
            }
            .map { ($0.title, $0.artist) }
            .removeDuplicates { $0 == $1 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] title, artist in
                self?.titleLabel.text = title
                self?.artistLabel.text = artist
            }
            .store(in: &cancellables)
    }
}
