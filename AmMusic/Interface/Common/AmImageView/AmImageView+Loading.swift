//
//  AmImageView+Loading.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import Kingfisher
import LRUCache
import UIKit

extension AmImageView {
    static let diskLoadQueue = DispatchQueue(
        label: "wiki.qaq.AmMusic.AmImageView.disk",
        qos: .userInitiated,
        attributes: .concurrent,
    )

    /// Load artwork from a URL.
    ///
    /// Memory-cached images are applied synchronously for zero-lag scrolling.
    /// Disk-cached images are decoded on a background queue, then promoted to
    /// the memory cache so the next hit is instant.  Network is the final fallback.
    func loadImage(url: URL?) {
        guard let url else {
            invalidateCurrentLoad()
            currentURL = nil
            previewCoordinator.clear()
            showPlaceholderState()
            return
        }

        guard url != currentURL else {
            if let image = imageView.image {
                onImageLoaded(url, image)
            }
            return
        }

        invalidateCurrentLoad()
        currentURL = url
        let ticket = loadID

        // Fast path: memory cache (no disk I/O)
        let cache = KingfisherManager.shared.cache
        let key = url.cacheKey
        if let cached = cache.retrieveImageInMemoryCache(forKey: key) {
            applyLoadedImage(cached, from: url)
            return
        }

        showPlaceholderState()
        startLoadingShimmer()
        loadFromDiskOrNetwork(url: url, key: key, ticket: ticket, cache: cache)
    }

    // MARK: - Loading Pipeline

    private func loadFromDiskOrNetwork(
        url: URL, key: String, ticket: UInt, cache: ImageCache,
    ) {
        Self.diskLoadQueue.async { [weak self] in
            guard let self else { return }
            guard cache.imageCachedType(forKey: key) == .disk else {
                DispatchQueue.main.async { [weak self] in
                    guard let self, loadID == ticket else { return }
                    startNetworkLoad(url: url, ticket: ticket)
                }
                return
            }
            decodeDiskImage(url: url, key: key, ticket: ticket, cache: cache)
        }
    }

    private func decodeDiskImage(
        url: URL, key: String, ticket: UInt, cache: ImageCache,
    ) {
        let redacted = Self.redactedURLDescription(for: url)
        cache.retrieveImageInDiskCache(forKey: key) { [weak self] result in
            guard let self else { return }
            switch result {
            case let .success(image):
                guard let image else {
                    DispatchQueue.main.async { [weak self] in
                        guard let self, loadID == ticket else { return }
                        startNetworkLoad(url: url, ticket: ticket)
                    }
                    return
                }
                // Force-decode off main thread so UIKit skips decode during rendering
                image.prepareForDisplay { [weak self] decoded in
                    let finalImage = decoded ?? image
                    // Promote to memory cache for instant future access
                    cache.store(finalImage, forKey: key, toDisk: false)
                    DispatchQueue.main.async { [weak self] in
                        guard let self, loadID == ticket else { return }
                        applyLoadedImage(finalImage, from: url)
                    }
                }
            case let .failure(error):
                DispatchQueue.main.async { [weak self] in
                    guard let self, loadID == ticket else { return }
                    AppLog.warning(
                        self,
                        "disk cache retrieval failed url=\(redacted) error=\(error.localizedDescription)",
                    )
                    startNetworkLoad(url: url, ticket: ticket)
                }
            }
        }
    }

    private func startNetworkLoad(url: URL, ticket: UInt) {
        imageView.kf.setImage(with: url, options: [.transition(.none)]) { [weak self] result in
            guard let self, loadID == ticket else { return }
            switch result {
            case let .success(value):
                applyLoadedImage(value.image, from: url)
            case let .failure(error):
                AppLog.error(
                    self,
                    "loadImage failure url=\(Self.redactedURLDescription(for: url)) error=\(error.localizedDescription)",
                )
                showPlaceholderState()
            }
        }
    }

    // MARK: - Apply

    func applyLoadedImage(_ image: UIImage, from url: URL) {
        imageView.image = image
        previewCoordinator.pendingImage = image
        previewCoordinator.pendingSourceURL = url
        previewCoordinator.previewItemURL = Self.previewFileCache.value(forKey: url)
        onImageLoaded(url, image)
        showImageState()
    }

    // MARK: - Helpers

    static func redactedURLDescription(for url: URL) -> String {
        let host = url.host ?? "local"
        let pathComponent = url.lastPathComponent.isEmpty ? "/" : url.lastPathComponent
        return "\(host)/\(pathComponent)"
    }
}
