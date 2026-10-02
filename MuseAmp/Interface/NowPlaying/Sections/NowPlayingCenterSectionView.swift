import SnapKit
import UIKit

@MainActor
class NowPlayingCenterSectionView: UIView {
    enum TransportLayout {
        case alignedWithArtwork
        case fullWidth(inset: CGFloat)
    }

    let avatarSectionView: NowPlayingAvatarSectionView
    let transportContentView: UIView
    private let transportLayout: TransportLayout

    var onArtworkLoaded: (URL, UIImage) -> Void = { _, _ in } {
        didSet {
            avatarSectionView.onArtworkLoaded = onArtworkLoaded
        }
    }

    init(environment: AppEnvironment, transportContentView: UIView, transportLayout: TransportLayout = .alignedWithArtwork) {
        avatarSectionView = NowPlayingAvatarSectionView(environment: environment)
        self.transportContentView = transportContentView
        self.transportLayout = transportLayout
        super.init(frame: UIScreen.main.bounds)
        backgroundColor = .clear
        setupViewHierarchy()
        setupLayout()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.backgroundColor = .clear
        scrollView.alwaysBounceVertical = false
        scrollView.alwaysBounceHorizontal = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        return scrollView
    }()

    private let stackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.distribution = .fill
        stackView.spacing = NowPlayingArtworkLayout.contentSpacing
        return stackView
    }()

    private func setupViewHierarchy() {
        addSubview(scrollView)
        scrollView.addSubview(stackView)
        stackView.addArrangedSubview(avatarSectionView)
        stackView.addArrangedSubview(transportContentView)
    }

    private func setupLayout() {
        scrollView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        stackView.snp.makeConstraints { make in
            make.top.greaterThanOrEqualTo(scrollView.contentLayoutGuide.snp.top).offset(NowPlayingArtworkLayout.topInset).priority(.high)
            make.leading.greaterThanOrEqualTo(scrollView.frameLayoutGuide.snp.leading).offset(NowPlayingArtworkLayout.horizontalInset).priority(.high)
            make.trailing.lessThanOrEqualTo(scrollView.frameLayoutGuide.snp.trailing).offset(-NowPlayingArtworkLayout.horizontalInset).priority(.high)
            make.centerY.equalTo(scrollView.frameLayoutGuide.snp.centerY).priority(.high)
            make.centerX.equalTo(scrollView.frameLayoutGuide.snp.centerX)
            make.top.greaterThanOrEqualTo(scrollView.contentLayoutGuide.snp.top)
            make.bottom.lessThanOrEqualTo(scrollView.contentLayoutGuide.snp.bottom)
            make.top.greaterThanOrEqualTo(scrollView.frameLayoutGuide.snp.top).offset(NowPlayingArtworkLayout.topInset).priority(NowPlayingArtworkLayout.contentPriority)
            make.bottom.lessThanOrEqualTo(scrollView.frameLayoutGuide.snp.bottom).offset(-NowPlayingArtworkLayout.bottomInset).priority(NowPlayingArtworkLayout.contentPriority)
        }

        avatarSectionView.snp.makeConstraints { make in
            // Below the column's fit constraints and the height cap, so the
            // artwork is what gives way when the column is too short, but
            // above the image view's content hugging, so a cover smaller
            // than the slot still fills it.
            make.width.equalTo(scrollView.frameLayoutGuide.snp.width).multipliedBy(0.8).priority(UILayoutPriority.defaultHigh - 1)
            make.width.lessThanOrEqualTo(scrollView.frameLayoutGuide.snp.width).multipliedBy(0.8)
            make.width.lessThanOrEqualTo(NowPlayingArtworkLayout.artworkMaxSize)
            make.height.lessThanOrEqualTo(avatarSectionView.snp.width).priority(.high)
            make.height.lessThanOrEqualTo(scrollView.frameLayoutGuide.snp.height).multipliedBy(0.6).priority(.high)
            make.height.equalTo(avatarSectionView.snp.width).priority(.low)
        }

        transportContentView.snp.makeConstraints { make in
            switch transportLayout {
            case .alignedWithArtwork:
                make.width.equalTo(avatarSectionView)
            case let .fullWidth(inset):
                make.width.equalTo(scrollView.frameLayoutGuide.snp.width).offset(-inset * 2).priority(.high)
            }
        }

        scrollView.contentLayoutGuide.snp.makeConstraints { make in
            make.width.equalTo(scrollView.frameLayoutGuide.snp.width)
        }

        avatarSectionView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        transportContentView.setContentCompressionResistancePriority(.required, for: .vertical)
    }
}
