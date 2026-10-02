import ColorfulX
import Kingfisher
import SnapKit
import SwifterSwift
import UIKit

@MainActor
final class TVRootBackgroundView: UIView {
    private let gradientView: AnimatedMulticolorGradientView = {
        let view = AnimatedMulticolorGradientView()
        view.isUserInteractionEnabled = false
        view.isOpaque = false
        view.backgroundColor = .clear
        view.speed /= 2
        view.bias /= 2
        view.noise = 0
        view.transitionSpeed *= 2
        view.renderScale = 1
        view.frameLimit = 30
        return view
    }()

    private let dimOverlay: UIView = {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        return view
    }()

    private var paletteTask: Task<Void, Never>?
    private var lastArtworkKey: String?
    private var colorCache: [String: [UIColor]] = [:]

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear

        addSubview(gradientView)
        addSubview(dimOverlay)

        gradientView.snp.makeConstraints { $0.edges.equalToSuperview() }
        dimOverlay.snp.makeConstraints { $0.edges.equalToSuperview() }

        applyIdleColors()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    func updateForArtwork(url: URL?) {
        let key = url?.absoluteString ?? ""
        guard key != lastArtworkKey else { return }
        lastArtworkKey = key

        paletteTask?.cancel()
        paletteTask = nil

        guard let url else {
            applyIdleColors()
            return
        }

        if let cached = colorCache[key] {
            applyColors(cached)
            return
        }

        paletteTask = Task { [weak self] in
            guard let self else { return }
            let image = await retrieveImage(from: url)
            guard !Task.isCancelled, let image else {
                applyIdleColors()
                return
            }
            let colors = await extractColors(from: image)
            guard !Task.isCancelled else { return }
            if let colors, !colors.isEmpty {
                colorCache[key] = colors
                applyColors(colors)
            } else {
                applyIdleColors()
            }
        }
    }

    private func applyIdleColors() {
        gradientView.setColors(
            ColorfulPreset.winter.colors,
            animated: true,
            repeats: true,
        )
    }

    private func applyColors(_ colors: [UIColor]) {
        gradientView.setColors(colors, animated: true, repeats: true)
    }

    private nonisolated func retrieveImage(from url: URL) async -> UIImage? {
        if url.isFileURL {
            return UIImage(contentsOfFile: url.path)
        }
        return await withCheckedContinuation { continuation in
            KingfisherManager.shared.retrieveImage(with: url) { result in
                switch result {
                case let .success(value): continuation.resume(returning: value.image)
                case .failure: continuation.resume(returning: nil)
                }
            }
        }
    }

    private nonisolated func extractColors(from image: UIImage) async -> [UIColor]? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let cgImage = image.cgImage else {
                    continuation.resume(returning: nil)
                    return
                }

                let size = 64
                let colorSpace = CGColorSpaceCreateDeviceRGB()
                var pixelData = [UInt8](repeating: 0, count: size * size * 4)
                guard let context = CGContext(
                    data: &pixelData,
                    width: size,
                    height: size,
                    bitsPerComponent: 8,
                    bytesPerRow: size * 4,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
                ) else {
                    continuation.resume(returning: nil)
                    return
                }
                context.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))

                var buckets: [Int: (r: Int, g: Int, b: Int, count: Int)] = [:]
                let step = 4
                for y in stride(from: 0, to: size, by: step) {
                    for x in stride(from: 0, to: size, by: step) {
                        let offset = (y * size + x) * 4
                        let r = Int(pixelData[offset])
                        let g = Int(pixelData[offset + 1])
                        let b = Int(pixelData[offset + 2])

                        let brightness = (r + g + b)
                        guard brightness > 60, brightness < 700 else { continue }
                        let saturation = max(r, g, b) - min(r, g, b)
                        guard saturation > 20 else { continue }

                        let key = (r / 32) * 100 + (g / 32) * 10 + (b / 32)
                        if var bucket = buckets[key] {
                            bucket.r += r
                            bucket.g += g
                            bucket.b += b
                            bucket.count += 1
                            buckets[key] = bucket
                        } else {
                            buckets[key] = (r, g, b, 1)
                        }
                    }
                }

                let sorted = buckets.values.sorted { $0.count > $1.count }
                let colors = sorted.prefix(4).map { bucket in
                    UIColor(
                        red: CGFloat(bucket.r / bucket.count) / 255.0,
                        green: CGFloat(bucket.g / bucket.count) / 255.0,
                        blue: CGFloat(bucket.b / bucket.count) / 255.0,
                        alpha: 1.0,
                    )
                }

                continuation.resume(returning: colors.isEmpty ? nil : colors)
            }
        }
    }
}
