import AmMusicDatabaseKit
import QuickLook
import UIKit

final class ImageQuickLookPreviewPresenter: NSObject {
    private weak var viewController: UIViewController?
    private var previewItemURL: URL?

    init(viewController: UIViewController?) {
        self.viewController = viewController
    }

    deinit {
        guard let previewItemURL else { return }
        try? FileManager.default.removeItem(at: previewItemURL)
    }

    func present(
        image: UIImage,
        fileName: String,
        preferredExtension: String = "jpg"
    ) {
        guard let viewController,
              let previewURL = makePreviewFileURL(
                  image: image,
                  fileName: fileName,
                  preferredExtension: preferredExtension
              )
        else {
            return
        }

        if let previousURL = previewItemURL, previousURL != previewURL {
            try? FileManager.default.removeItem(at: previousURL)
        }
        previewItemURL = previewURL

        let previewController = QLPreviewController()
        previewController.dataSource = self
        viewController.present(previewController, animated: true)
    }
}

private extension ImageQuickLookPreviewPresenter {
    func makePreviewFileURL(
        image: UIImage,
        fileName: String,
        preferredExtension: String
    ) -> URL? {
        let fileExtension = preferredExtension.isEmpty ? "jpg" : preferredExtension
        let sanitizedBaseName = sanitizeDisplayFileName(fileName, fallback: "Preview")
        let previewURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(sanitizedBaseName)-\(UUID().uuidString).\(fileExtension)")

        let data: Data? = if fileExtension.lowercased() == "png" {
            image.pngData()
        } else {
            image.jpegData(compressionQuality: 0.98)
        }

        guard let data else {
            AppLog.warning(self, "makePreviewFileURL no image data generated")
            return nil
        }

        do {
            try data.write(to: previewURL, options: .atomic)
            return previewURL
        } catch {
            AppLog.error(self, "makePreviewFileURL write failed error=\(error.localizedDescription)")
            return nil
        }
    }
}

extension ImageQuickLookPreviewPresenter: QLPreviewControllerDataSource {
    func numberOfPreviewItems(in _: QLPreviewController) -> Int {
        previewItemURL == nil ? 0 : 1
    }

    func previewController(_: QLPreviewController, previewItemAt _: Int) -> QLPreviewItem {
        previewItemURL! as NSURL
    }
}
