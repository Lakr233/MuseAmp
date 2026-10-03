//
//  NowPlayingArtworkBackgroundCoordinator.swift
//  MuseAmp
//
//  Created by @Lakr233 on 2026/04/11.
//

import DominantColors
import Kingfisher
import LRUCache
import UIKit

@MainActor
final class NowPlayingArtworkBackgroundCoordinator {
    typealias BackgroundSource = NowPlayingControlIslandViewModel.BackgroundSource

    private let backgroundView: NowPlayingArtworkBackgroundView
    private let logOwner: String
    private let currentArtworkURL: () -> URL?
    private let idleColors: [UIColor]

    private var paletteTask: Task<Void, Never>?
    private(set) var lastBackgroundSource: BackgroundSource = .idle
    private let artworkPaletteCache = LRUCache<String, [UIColor]>(countLimit: 32)

    init(
        backgroundView: NowPlayingArtworkBackgroundView,
        logOwner: String,
        currentArtworkURL: @escaping () -> URL?,
        idleColors: [UIColor] = NowPlayingArtworkBackgroundCoordinator.defaultIdleColors(),
    ) {
        self.backgroundView = backgroundView
        self.logOwner = logOwner
        self.currentArtworkURL = currentArtworkURL
        self.idleColors = idleColors
    }

    deinit {
        paletteTask?.cancel()
    }

    func applyIdleBackground() {
        paletteTask?.cancel()
        paletteTask = nil
        lastBackgroundSource = .idle
        backgroundView.apply(colors: idleColors)
    }

    func cancel() {
        paletteTask?.cancel()
        paletteTask = nil
    }

    func update(
        using backgroundSource: BackgroundSource,
        animated _: Bool,
    ) {
        switch (lastBackgroundSource, backgroundSource) {
        case let (.artwork(previousURL), .artwork(currentURL)):
            if previousURL == currentURL,
               artworkPaletteCache.value(forKey: currentURL.absoluteString) != nil
            {
                return
            }
        case (.idle, .idle):
            return
        default:
            break
        }

        lastBackgroundSource = backgroundSource
        cancel()

        switch backgroundSource {
        case .idle:
            applyIdleBackground()
        case let .artwork(url):
            if let cachedColors = artworkPaletteCache.value(forKey: url.absoluteString) {
                backgroundView.apply(colors: cachedColors)
                return
            }

            paletteTask = Task { [weak self] in
                guard let self else { return }
                let colors = await paletteColors(for: url)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard self.lastBackgroundSource == backgroundSource else { return }
                    if let colors {
                        self.artworkPaletteCache.setValue(colors, forKey: url.absoluteString)
                        self.backgroundView.apply(colors: colors)
                    } else {
                        self.backgroundView.apply(colors: self.idleColors)
                    }
                }
            }
        }
    }

    func updateFromDisplayedArtwork(url: URL, image: UIImage) {
        guard case let .artwork(currentURL) = lastBackgroundSource,
              currentURL == url
        else {
            return
        }

        if let cachedColors = artworkPaletteCache.value(forKey: url.absoluteString) {
            backgroundView.apply(colors: cachedColors)
            return
        }

        cancel()
        paletteTask = Task { [weak self] in
            guard let self else { return }
            let colors = await extractPalette(from: image)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard self.currentArtworkURL() == url else { return }
                guard let colors else { return }
                self.artworkPaletteCache.setValue(colors, forKey: url.absoluteString)
                self.backgroundView.apply(colors: colors)
            }
        }
    }

    nonisolated static func defaultIdleColors() -> [UIColor] {
        [
            UIColor(white: 0.45, alpha: 1),
            UIColor(white: 0.50, alpha: 1),
            UIColor(white: 0.52, alpha: 1),
            UIColor(white: 0.48, alpha: 1),
        ]
    }

    private func paletteColors(for artworkURL: URL) async -> [UIColor]? {
        guard let image = await retrieveArtworkImage(from: artworkURL) else {
            return nil
        }
        return await extractPalette(from: image)
    }

    private func retrieveArtworkImage(from artworkURL: URL) async -> UIImage? {
        if artworkURL.isFileURL {
            let image = UIImage(contentsOfFile: artworkURL.path)
            if image == nil {
                AppLog.warning(
                    logOwner,
                    "artwork background load failed source=file artwork=\(nowPlayingLogURLDescription(artworkURL))",
                )
            }
            return image
        }

        let artworkDescription = nowPlayingLogURLDescription(artworkURL)
        let logOwner = logOwner
        return await withCheckedContinuation { continuation in
            KingfisherManager.shared.retrieveImage(with: artworkURL) { result in
                switch result {
                case let .success(value):
                    continuation.resume(returning: value.image)
                case let .failure(error):
                    AppLog.warning(
                        logOwner,
                        "artwork background load failed source=remote artwork=\(artworkDescription) error=\(error)",
                    )
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func extractPalette(from image: UIImage) async -> [UIColor]? {
        let imageData = image.pngData() ?? image.jpegData(compressionQuality: 1)
        let logOwner = logOwner
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let imageData,
                      let decodedImage = UIImage(data: imageData)
                else {
                    AppLog.warning(logOwner, "artwork background palette decode failed")
                    continuation.resume(returning: nil)
                    return
                }

                let extracted = (try? DominantColors.dominantColors(
                    uiImage: decodedImage,
                    quality: .best,
                    maxCount: 4,
                    options: [.excludeBlack, .excludeWhite, .excludeGray],
                )) ?? []

                continuation.resume(returning: extracted)
            }
        }
    }
}
