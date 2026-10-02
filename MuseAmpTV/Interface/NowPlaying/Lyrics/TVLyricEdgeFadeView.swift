//
//  TVLyricEdgeFadeView.swift
//  MuseAmpTV
//
//  Variable-blur edge fade overlay for the lyric view. Uses the same
//  private CAFilter approach as EdgeFadeBlurView on iOS.
//

import UIKit

@MainActor
final class TVLyricEdgeFadeView: UIVisualEffectView {
    nonisolated enum Direction {
        case topFade
        case bottomFade
    }

    private let direction: Direction

    init(direction: Direction) {
        self.direction = direction
        super.init(effect: UIBlurEffect(style: .dark))
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

    override func traitCollectionDidChange(_: UITraitCollection?) {}

    private func applyVariableBlurIfAvailable() {
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

        let gradientImage = makeGradientImage()
        let maxBlurRadius: CGFloat = 2
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

    private func makeGradientImage() -> CGImage? {
        let gradientLayer = CAGradientLayer()
        gradientLayer.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        switch direction {
        case .topFade:
            gradientLayer.colors = [UIColor.black.cgColor, UIColor.clear.cgColor]
        case .bottomFade:
            gradientLayer.colors = [UIColor.clear.cgColor, UIColor.black.cgColor]
        }
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 1)
        gradientLayer.locations = [0, 1]

        let renderer = UIGraphicsImageRenderer(size: gradientLayer.bounds.size)
        let image = renderer.image { context in
            gradientLayer.render(in: context.cgContext)
        }
        return image.cgImage
    }
}
