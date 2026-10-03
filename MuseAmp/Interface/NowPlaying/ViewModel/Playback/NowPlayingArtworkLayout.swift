import UIKit

nonisolated enum NowPlayingArtworkLayout {
    static let horizontalInset: CGFloat = 32
    static let topInset: CGFloat = 32
    static let bottomInset: CGFloat = 32
    static let contentSpacing: CGFloat = 28
    static let artworkCornerRadius: CGFloat = 28
    static let artworkInset: CGFloat = 32
    static let artworkMaxSize: CGFloat = 512
    /// Holds the title, progress and transport rows and the column's top and
    /// bottom insets. It sits above everything that sizes the artwork, so a
    /// short column shrinks the artwork instead of squeezing the title or
    /// drawing the controls over the artwork.
    static let contentPriority = UILayoutPriority.required - 1
}
