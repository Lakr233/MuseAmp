import AVKit
import SnapKit
import Then
import UIKit

enum NowPlayingArtworkLayout {
    static let horizontalInset: CGFloat = 28
    static let topInset: CGFloat = 24
    static let bottomInset: CGFloat = 28
    static let contentSpacing: CGFloat = 28
    static let artworkCornerRadius: CGFloat = 28
    static let artworkInset: CGFloat = 32
    static let artworkMaxSize: CGFloat = 512
}

final class NowPlayingCenterSectionView: UIView {
    let avatarSectionView = NowPlayingAvatarSectionView()
    let transportView = NowPlayingTransportView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        setupViewHierarchy()
        setupLayout()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    var onArtworkLoaded: ((URL, UIImage) -> Void)? {
        didSet {
            avatarSectionView.onArtworkLoaded = onArtworkLoaded
        }
    }

    func updateArtwork(url: URL?) {
        avatarSectionView.updateArtwork(url: url)
    }

    func bindTransport(to viewModel: NowPlayingControlIslandViewModel) {
        transportView.bind(to: viewModel)
    }

    func configureTransport(
        with content: NowPlayingControlIslandViewModel.Content,
        animated: Bool
    ) {
        transportView.configure(with: content, animated: animated)
    }

    func installRoutePickerView(_ routePickerView: AVRoutePickerView) {
        transportView.installRoutePickerView(routePickerView)
    }

    func updateCurrentLyricLine(_ line: String?) {
        transportView.updateCurrentLyricLine(line)
    }

    func setAnimationsSuspended(_ suspended: Bool) {
        transportView.setAnimationsSuspended(suspended)
    }

    private let scrollView = UIScrollView().then {
        $0.backgroundColor = .clear
        $0.alwaysBounceVertical = false
        $0.alwaysBounceHorizontal = false
        $0.showsVerticalScrollIndicator = false
        $0.showsHorizontalScrollIndicator = false
        $0.contentInsetAdjustmentBehavior = .never
    }

    private let stackView = UIStackView().then {
        $0.axis = .vertical
        $0.alignment = .center
        $0.distribution = .fill
        $0.spacing = NowPlayingArtworkLayout.contentSpacing
    }

    private func setupViewHierarchy() {
        addSubview(scrollView)
        scrollView.addSubview(stackView)
        stackView.addArrangedSubview(avatarSectionView)
        stackView.addArrangedSubview(transportView)
    }

    private func setupLayout() {
        scrollView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        stackView.snp.makeConstraints { make in
            make.top.greaterThanOrEqualTo(scrollView.contentLayoutGuide.snp.top).offset(NowPlayingArtworkLayout.topInset).priority(.high)
            make.centerX.equalTo(scrollView.frameLayoutGuide)
            make.centerY.equalTo(scrollView.frameLayoutGuide).priority(.high)
            make.leading.greaterThanOrEqualTo(scrollView.frameLayoutGuide).offset(NowPlayingArtworkLayout.horizontalInset).priority(.high)
            make.trailing.lessThanOrEqualTo(scrollView.frameLayoutGuide).offset(-NowPlayingArtworkLayout.horizontalInset).priority(.high)
            make.top.greaterThanOrEqualTo(scrollView.contentLayoutGuide).priority(.required)
            make.bottom.lessThanOrEqualTo(scrollView.contentLayoutGuide).priority(.required)
        }

        avatarSectionView.snp.makeConstraints { make in
            make.width.equalTo(scrollView.frameLayoutGuide).multipliedBy(0.9).priority(.high)
            make.width.lessThanOrEqualTo(scrollView.frameLayoutGuide).multipliedBy(0.9)
            make.width.lessThanOrEqualTo(NowPlayingArtworkLayout.artworkMaxSize)
            make.height.equalTo(avatarSectionView.snp.width)
        }

        transportView.snp.makeConstraints { make in
            make.leading.trailing.equalTo(scrollView.frameLayoutGuide).priority(.high)
        }

        scrollView.contentLayoutGuide.snp.makeConstraints { make in
            make.width.equalTo(scrollView.frameLayoutGuide)
        }
    }
}
