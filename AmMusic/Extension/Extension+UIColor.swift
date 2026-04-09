import UIKit

extension UIColor {
    func shiftedHue(
        by delta: CGFloat,
        saturationMultiplier: CGFloat = 1,
        brightnessMultiplier: CGFloat = 1
    ) -> UIColor {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0

        guard getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
            return withAlphaComponent(1)
        }

        let shiftedHue = (hue + delta).truncatingRemainder(dividingBy: 1)
        let normalizedHue = shiftedHue < 0 ? shiftedHue + 1 : shiftedHue
        let normalizedSaturation = min(max(saturation * saturationMultiplier, 0), 1)
        let normalizedBrightness = min(max(brightness * brightnessMultiplier, 0), 1)
        return UIColor(
            hue: normalizedHue,
            saturation: normalizedSaturation,
            brightness: normalizedBrightness,
            alpha: 1
        )
    }
}
