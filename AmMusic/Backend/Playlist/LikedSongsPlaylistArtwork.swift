import UIKit

enum LikedSongsPlaylistArtwork {
    private static let canvasSize = CGSize(width: 1024, height: 1024)
    private static let symbolSideLength: CGFloat = 512

    static func makePNGData() -> Data? {
        makeImage().pngData()
    }

    static func makeImage() -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = true
        format.scale = 1

        return UIGraphicsImageRenderer(size: canvasSize, format: format).image { context in
            let rect = CGRect(origin: .zero, size: canvasSize)
            let accentColor = UIColor(named: "AccentColor") ?? .systemPink
            accentColor.setFill()
            context.cgContext.fill(rect)

            let heartRect = CGRect(
                x: (canvasSize.width - symbolSideLength) / 2,
                y: (canvasSize.height - symbolSideLength) / 2,
                width: symbolSideLength,
                height: symbolSideLength
            )

            let configuration = UIImage.SymbolConfiguration(pointSize: symbolSideLength, weight: .regular)
            let heartImage = UIImage(systemName: "heart.fill", withConfiguration: configuration)?
                .withTintColor(.white, renderingMode: .alwaysOriginal)
            if let heartImage {
                let drawRect = aspectFitRect(for: heartImage.size, in: heartRect)
                heartImage.draw(in: drawRect)
            }
        }
    }

    static func aspectFitRect(for contentSize: CGSize, in boundingRect: CGRect) -> CGRect {
        guard contentSize.width > 0, contentSize.height > 0 else {
            return boundingRect
        }

        let scale = min(
            boundingRect.width / contentSize.width,
            boundingRect.height / contentSize.height
        )
        let drawSize = CGSize(
            width: contentSize.width * scale,
            height: contentSize.height * scale
        )

        return CGRect(
            x: boundingRect.midX - drawSize.width / 2,
            y: boundingRect.midY - drawSize.height / 2,
            width: drawSize.width,
            height: drawSize.height
        )
    }
}
