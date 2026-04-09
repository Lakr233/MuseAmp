import AVKit
import UIKit

@MainActor
final class NowPlayingRoutePickerPresenter: NSObject, AVRoutePickerViewDelegate {
    lazy var routePickerView: AVRoutePickerView = {
        let view = AdaptiveRoutePickerView()
        view.delegate = self
        view.backgroundColor = .clear
        view.prioritizesVideoDevices = false
        view.largeContentImageInsets = .zero
        return view
    }()
}

private final class AdaptiveRoutePickerView: AVRoutePickerView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        updateColors()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateColors()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        guard previousTraitCollection?.hasDifferentColorAppearance(comparedTo: traitCollection) ?? true else {
            return
        }

        updateColors()
    }

    private func updateColors() {
        let resolvedColor = UIColor.white.resolvedColor(with: traitCollection)
        tintColor = resolvedColor
        activeTintColor = resolvedColor
    }
}
