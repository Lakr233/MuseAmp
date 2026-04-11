//
//  AmImageView+Preview.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import LRUCache
import QuickLook
import UIKit

// MARK: - QuickLook Preview

extension AmImageView {
    static let previewFileCache = LRUCache<URL, URL>(countLimit: 100)

    @objc func handleTap() {
        guard allowsPreviewOnTap,
              let viewController = nearestViewController()
        else {
            return
        }

        // Lazily create preview file on first tap
        if previewCoordinator.previewItemURL == nil {
            previewCoordinator.previewItemURL = makePreviewFileURL(
                from: previewCoordinator.pendingImage,
                sourceURL: previewCoordinator.pendingSourceURL,
            )
        }

        guard previewCoordinator.previewItemURL != nil else { return }

        let previewController = QLPreviewController()
        previewController.dataSource = previewCoordinator
        viewController.present(previewController, animated: true)
    }

    private func makePreviewFileURL(from image: UIImage?, sourceURL: URL?) -> URL? {
        guard let image, let sourceURL else { return nil }

        if let cached = Self.previewFileCache.value(forKey: sourceURL) {
            return cached
        }

        let ext = sourceURL.pathExtension.isEmpty ? "jpg" : sourceURL.pathExtension
        let fileName = "am-preview-\(UUID().uuidString).\(ext)"
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        let data: Data? = if ext.lowercased() == "png" {
            image.pngData()
        } else {
            image.jpegData(compressionQuality: 0.98)
        }

        guard let data else {
            AppLog.warning(self, "makePreviewFileURL no data generated")
            return nil
        }

        do {
            try data.write(to: fileURL, options: .atomic)
            Self.previewFileCache.setValue(fileURL, forKey: sourceURL)
            return fileURL
        } catch {
            AppLog.error(self, "makePreviewFileURL write failed error=\(error.localizedDescription)")
            return nil
        }
    }

    private func nearestViewController() -> UIViewController? {
        sequence(first: next) { $0?.next }
            .first { $0 is UIViewController } as? UIViewController
    }
}

// MARK: - PreviewCoordinator

final class PreviewCoordinator: NSObject, QLPreviewControllerDataSource {
    var previewItemURL: URL?
    var pendingImage: UIImage?
    var pendingSourceURL: URL?

    func clear() {
        previewItemURL = nil
        pendingImage = nil
        pendingSourceURL = nil
    }

    func numberOfPreviewItems(in _: QLPreviewController) -> Int {
        previewItemURL == nil ? 0 : 1
    }

    func previewController(_: QLPreviewController, previewItemAt _: Int) -> QLPreviewItem {
        previewItemURL! as NSURL
    }
}
