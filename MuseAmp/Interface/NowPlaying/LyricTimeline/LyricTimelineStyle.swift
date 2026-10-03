import UIKit

nonisolated enum LyricTimelineAnimation {
    static let plainRevealTranslationY: CGFloat = 12
}

nonisolated enum LyricTimelineLineStyle {
    static let textFont = UIFontMetrics(forTextStyle: .title2).scaledFont(
        for: .systemFont(ofSize: 28, weight: .bold),
    )
    static let activeAlpha: CGFloat = 1.0
    static let inactiveAlpha: CGFloat = 0.25
    static let estimatedLineHeight = ceil(textFont.lineHeight)
}
