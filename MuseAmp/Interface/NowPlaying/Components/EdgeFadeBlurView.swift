import UIKit

@MainActor
final class EdgeFadeBlurView: UIVisualEffectView {
    nonisolated enum Direction {
        case blurredTopClearBottom
        case blurredBottomClearTop
    }

    private let direction: Direction

    init(
        effectStyle: UIBlurEffect.Style = .dark,
        direction: Direction,
    ) {
        self.direction = direction
        super.init(effect: UIBlurEffect(style: effectStyle))
        isUserInteractionEnabled = false
        alpha = 1
        applyVariableBlurIfAvailable()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard let window, let backdropLayer = subviews.first?.layer else {
            return
        }
        backdropLayer.setValue(window.traitCollection.displayScale, forKey: "scale")
    }

    override func traitCollectionDidChange(_: UITraitCollection?) {
        // The vendored VariableBlur implementation intentionally skips the
        // superclass implementation because it can crash while reconfiguring
        // the private backdrop filter on appearance changes.
    }

    private func applyVariableBlurIfAvailable(maxBlurRadius: CGFloat = 2, startOffset: CGFloat = 0) {
        let className = String("retliFAC".reversed())
        guard let filterClass = NSClassFromString(className) as? NSObject.Type else {
            hideTintSubviews()
            return
        }
        let selectorName = String(":epyThtiWretlif".reversed())
        guard let variableBlur = filterClass
            .perform(NSSelectorFromString(selectorName), with: "variableBlur")?
            .takeUnretainedValue() as? NSObject
        else {
            hideTintSubviews()
            return
        }

        let gradientImage = makeGradientImage(
            startOffset: startOffset,
            direction: direction,
        )
        variableBlur.setValue(maxBlurRadius, forKey: "inputRadius")
        variableBlur.setValue(gradientImage, forKey: "inputMaskImage")
        variableBlur.setValue(true, forKey: "inputNormalizeEdges")

        let backdropLayer = subviews.first?.layer
        backdropLayer?.filters = [variableBlur]
        hideTintSubviews()
    }

    private func hideTintSubviews() {
        for subview in subviews.dropFirst() {
            subview.alpha = 0
        }
    }

    private func makeGradientImage(
        width: CGFloat = 100,
        height: CGFloat = 100,
        startOffset: CGFloat,
        direction: Direction,
    ) -> CGImage? {
        let gradientLayer = CAGradientLayer()
        gradientLayer.frame = CGRect(x: 0, y: 0, width: width, height: height)
        switch direction {
        case .blurredTopClearBottom:
            gradientLayer.colors = [UIColor.black.cgColor, UIColor.clear.cgColor]
        case .blurredBottomClearTop:
            gradientLayer.colors = [UIColor.clear.cgColor, UIColor.black.cgColor]
        }
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 1)
        gradientLayer.locations = [
            NSNumber(value: max(startOffset, 0)),
            1,
        ]

        let renderer = UIGraphicsImageRenderer(size: gradientLayer.bounds.size)
        let image = renderer.image { context in
            gradientLayer.render(in: context.cgContext)
        }
        return image.cgImage
    }
}
