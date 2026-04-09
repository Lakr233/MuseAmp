import ColorfulX
import SnapKit
import Then
import UIKit

final class NowPlayingArtworkBackgroundView: UIView {
    private enum Appearance {
        static let speed: Double = 0.2
        static let bias: Double = 0.1
        static let noise: Double = 0
        static let transitionSpeed: Double = 1
        static let renderScale: Double = 0.25
    }

    private let gradientView = AnimatedMulticolorGradientView().then {
        $0.isUserInteractionEnabled = false
        $0.isOpaque = false
        $0.backgroundColor = .clear
        $0.speed = Appearance.speed
        $0.bias = Appearance.bias
        $0.noise = Appearance.noise
        $0.transitionSpeed = Appearance.transitionSpeed
        $0.renderScale = Appearance.renderScale
        $0.frameLimit = 30
    }

    private let overlayView = UIView().then {
        $0.isUserInteractionEnabled = false
        $0.backgroundColor = .clear
    }

    private var isAnimationSuspended = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        clipsToBounds = true
        backgroundColor = .clear
        setupViewHierarchy()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    func apply(colors: [UIColor]) {
        gradientView.setColors(colors, animated: true, repeats: true)
    }

    func setAnimationSuspended(_ suspended: Bool) {
        guard isAnimationSuspended != suspended else {
            return
        }

        isAnimationSuspended = suspended
        gradientView.speed = suspended ? 0 : Appearance.speed
        gradientView.transitionSpeed = suspended ? 0 : Appearance.transitionSpeed
    }

    private func setupViewHierarchy() {
        addSubview(gradientView)
        addSubview(overlayView)

        gradientView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        overlayView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }
}
