//
//  TrackNumberBadge.swift
//  MuseAmp
//
//  Created by @Lakr233 on 2026/10/03.
//

import LRUCache
import UIKit

/// Track numbers drawn as filled-circle badges.
///
/// SF Symbols only ships `0.circle.fill` through `50.circle.fill`. Numbers
/// with a symbol use it; any other number is drawn to match: the same filled
/// circle with the number knocked out, widened into a capsule once the number
/// no longer fits the circle.
@MainActor
enum TrackNumberBadge {
    struct Rendering {
        let image: UIImage
        /// Image width relative to the `N.circle.fill` symbols: 1 for a
        /// circle, more for a capsule. Scale the image view's width by it.
        let widthRatio: CGFloat
    }

    private nonisolated enum Metrics {
        /// Digit cap height as a fraction of the circle, measured against
        /// `50.circle.fill`.
        static let digitHeight: CGFloat = 0.43
        /// Width that two digits may take inside the circle, as a fraction
        /// of its diameter. Wider digits are squeezed horizontally, like the
        /// two-digit symbols.
        static let twoDigitWidth: CGFloat = 0.56
        /// Resolution used to find the circle inside the reference symbol.
        static let scanScale: CGFloat = 4
    }

    private nonisolated struct CacheKey: Hashable {
        let number: Int
        let pointSize: CGFloat
        let weight: CGFloat
    }

    private static let cache = LRUCache<CacheKey, Rendering>(countLimit: 256)

    static func rendering(
        for number: Int,
        pointSize: CGFloat,
        weight: UIFont.Weight = .regular,
    ) -> Rendering? {
        let configuration = UIImage.SymbolConfiguration(
            font: .systemFont(ofSize: pointSize, weight: weight),
        )
        if let symbol = UIImage(systemName: "\(number).circle.fill", withConfiguration: configuration) {
            return Rendering(image: symbol, widthRatio: 1)
        }

        let key = CacheKey(number: number, pointSize: pointSize, weight: weight.rawValue)
        if let cached = cache.value(forKey: key) {
            return cached
        }
        guard let reference = UIImage(systemName: "circle.fill", withConfiguration: configuration),
              let circle = circleBounds(in: reference)
        else {
            AppLog.warning("TrackNumberBadge", "reference circle unavailable number=\(number) pointSize=\(pointSize)")
            return nil
        }
        let rendering = drawBadge(number: number, reference: reference, circle: circle)
        cache.setValue(rendering, forKey: key)
        return rendering
    }
}

private extension TrackNumberBadge {
    static func drawBadge(number: Int, reference: UIImage, circle: CGRect) -> Rendering {
        let text = "\(number)" as NSString
        let font = digitFont(circleHeight: circle.height)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.black]
        let pairWidth = ("00" as NSString).size(withAttributes: attributes).width
        let squeeze = min(1, circle.width * Metrics.twoDigitWidth / pairWidth)
        let textWidth = text.size(withAttributes: attributes).width * squeeze
        let horizontalPadding = circle.width * (1 - Metrics.twoDigitWidth)
        let format = UIGraphicsImageRendererFormat.preferred()
        format.opaque = false
        // Whole pixels, so the capsule fills the canvas the renderer returns.
        let extraWidth = (max(0, textWidth + horizontalPadding - circle.width) * format.scale).rounded(.up) / format.scale
        let capsule = CGRect(x: circle.minX, y: circle.minY, width: circle.width + extraWidth, height: circle.height)
        let canvasSize = CGSize(width: reference.size.width + extraWidth, height: reference.size.height)

        let drawn = UIGraphicsImageRenderer(size: canvasSize, format: format).image { context in
            UIColor.black.setFill()
            UIBezierPath(roundedRect: capsule, cornerRadius: capsule.height / 2).fill()

            let cgContext = context.cgContext
            cgContext.setBlendMode(.destinationOut)
            let baseline = capsule.midY + font.capHeight / 2
            cgContext.translateBy(x: capsule.midX - textWidth / 2, y: baseline - font.ascender)
            cgContext.scaleBy(x: squeeze, y: 1)
            text.draw(at: .zero, withAttributes: attributes)
        }

        var image = drawn
            .withRenderingMode(.alwaysTemplate)
            .withAlignmentRectInsets(reference.alignmentRectInsets)
        if let baseline = reference.baselineOffsetFromBottom {
            image = image.withBaselineOffset(fromBottom: baseline)
        }
        image.accessibilityLabel = NumberFormatter.localizedString(from: NSNumber(value: number), number: .none)
        return Rendering(image: image, widthRatio: image.size.width / reference.size.width)
    }

    /// Rounded digits like the symbols'. Bold, because squeezing two digits
    /// into the circle thins their vertical strokes.
    static func digitFont(circleHeight: CGFloat) -> UIFont {
        let system = UIFont.systemFont(ofSize: 10, weight: .bold)
        let descriptor = system.fontDescriptor.withDesign(.rounded) ?? system.fontDescriptor
        let probe = UIFont(descriptor: descriptor, size: 10)
        let size = 10 * circleHeight * Metrics.digitHeight / probe.capHeight
        return UIFont(descriptor: descriptor, size: size)
    }

    /// The symbol image has padding around its glyph, so the circle is found
    /// by rasterizing `circle.fill` and measuring its opaque pixels.
    static func circleBounds(in reference: UIImage) -> CGRect? {
        let scale = Metrics.scanScale
        let width = Int((reference.size.width * scale).rounded(.up))
        let height = Int((reference.size.height * scale).rounded(.up))
        guard width > 0, height > 0 else { return nil }

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let rendered = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
            ) else {
                return false
            }
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: scale, y: -scale)
            UIGraphicsPushContext(context)
            reference.withTintColor(.black, renderingMode: .alwaysOriginal).draw(at: .zero)
            UIGraphicsPopContext()
            return true
        }
        guard rendered else { return nil }

        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1
        for y in 0 ..< height {
            for x in 0 ..< width where pixels[(y * width + x) * 4 + 3] > 127 {
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return CGRect(
            x: CGFloat(minX) / scale,
            y: CGFloat(minY) / scale,
            width: CGFloat(maxX - minX + 1) / scale,
            height: CGFloat(maxY - minY + 1) / scale,
        )
    }
}
