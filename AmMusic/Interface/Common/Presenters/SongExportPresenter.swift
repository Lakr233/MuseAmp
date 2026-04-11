//
//  SongExportPresenter.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import AlertController
import AmMusicDatabaseKit
import UIKit

final class SongExportPresenter {
    private weak var viewController: UIViewController?
    private let lyricsStore: LyricsCacheStore?
    private let locations: LibraryPaths?
    private let apiClient: APIClient?

    init(
        viewController: UIViewController?,
        lyricsStore: LyricsCacheStore? = nil,
        locations: LibraryPaths? = nil,
        apiClient: APIClient? = nil,
    ) {
        self.viewController = viewController
        self.lyricsStore = lyricsStore
        self.locations = locations
        self.apiClient = apiClient
    }

    func present(
        items: [SongExportItem],
        barButtonItem: UIBarButtonItem? = nil,
        sourceView: UIView? = nil,
        sourceRect: CGRect? = nil,
    ) {
        guard let viewController else {
            return
        }

        guard !items.isEmpty else {
            return
        }

        let progressAlert = AlertProgressIndicatorViewController(
            title: String(localized: "Preparing"),
            message: String(localized: "Preparing files..."),
        )
        viewController.present(progressAlert, animated: true) {
            Task { @MainActor [weak viewController] in
                guard let viewController else {
                    return
                }

                guard let builder = self.makePreparedTrackBuilder() else {
                    progressAlert.dismiss(animated: true) {
                        self.presentExportError(
                            from: viewController,
                            message: String(localized: "Export is not available because the local library services are not ready."),
                        )
                    }
                    return
                }

                do {
                    let batch = try await builder.prepareBatch(
                        deviceName: UIDevice.current.name,
                        items: items,
                        progress: { current, total in
                            progressAlert.progressContext.purpose(
                                message: "\(current) / \(max(total, 1))",
                            )
                        },
                    )

                    progressAlert.dismiss(animated: true) {
                        self.presentShareSheet(
                            urls: batch.preparedURLs,
                            cleanupDirectoryURL: batch.cleanupDirectoryURL,
                            from: viewController,
                            barButtonItem: barButtonItem,
                            sourceView: sourceView,
                            sourceRect: sourceRect,
                        )
                    }
                } catch {
                    AppLog.error("SongExportPresenter", "prepareBatch failed: \(error.localizedDescription)")
                    progressAlert.dismiss(animated: true) {
                        self.presentExportError(
                            from: viewController,
                            message: error.localizedDescription,
                        )
                    }
                }
            }
        }
    }
}

private extension SongExportPresenter {
    func makePreparedTrackBuilder() -> SyncPreparedTrackBuilder? {
        guard let lyricsStore,
              let locations,
              let apiClient
        else {
            return nil
        }
        return SyncPreparedTrackBuilder(
            paths: locations,
            lyricsCacheStore: lyricsStore,
            apiClient: apiClient,
        )
    }

    func presentExportError(from viewController: UIViewController, message: String) {
        let alert = AlertViewController(
            title: String(localized: "Export Failed"),
            message: message,
        ) { context in
            context.addAction(title: String(localized: "OK"), attribute: .accent) { context.dispose() }
        }
        viewController.present(alert, animated: true)
    }

    func presentShareSheet(
        urls: [URL],
        cleanupDirectoryURL: URL?,
        from viewController: UIViewController,
        barButtonItem: UIBarButtonItem?,
        sourceView: UIView?,
        sourceRect: CGRect?,
    ) {
        let controller = UIActivityViewController(activityItems: urls, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            self.cleanupExportDirectory(cleanupDirectoryURL)
        }

        if let popover = controller.popoverPresentationController {
            if let barButtonItem {
                popover.barButtonItem = barButtonItem
            } else if let resolvedSourceView = sourceView ?? viewController.view {
                popover.sourceView = resolvedSourceView
                popover.sourceRect = sourceRect ?? resolvedSourceView.bounds
            }
        }

        viewController.present(controller, animated: true)
    }

    func cleanupExportDirectory(_ cleanupDirectoryURL: URL?) {
        guard let cleanupDirectoryURL else { return }
        do {
            try FileManager.default.removeItem(at: cleanupDirectoryURL)
        } catch {
            AppLog.error("SongExportPresenter", "Failed to remove export temp dir error=\(error.localizedDescription)")
        }
    }
}
