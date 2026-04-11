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

        let (urls, cleanupDirectoryURL) = makeExportURLs(for: items)
        guard !urls.isEmpty else {
            return
        }

        let itemsByURL = Dictionary(
            uniqueKeysWithValues: zip(urls, items).compactMap { url, item -> (URL, SongExportItem)? in
                url == item.sourceURL ? nil : (url, item)
            },
        )
        let lyricsStore = lyricsStore

        let locations = locations
        let apiClient = apiClient
        let exportInfos: [(URL, ExportMetadataProcessor.ExportInfo)] = itemsByURL.map { url, item in
            let lyrics = lyricsStore?.lyrics(for: item.trackID)
            let info = ExportMetadataProcessor.ExportInfo(
                trackID: item.trackID,
                albumID: item.albumID,
                artworkURL: item.artworkURL,
                lyrics: lyrics,
                title: item.title,
                artistName: item.artistName,
                albumName: item.albumName,
            )
            return (url, info)
        }

        guard !exportInfos.isEmpty else {
            presentShareSheet(
                urls: urls,
                cleanupDirectoryURL: cleanupDirectoryURL,
                from: viewController,
                barButtonItem: barButtonItem,
                sourceView: sourceView,
                sourceRect: sourceRect,
            )
            return
        }

        // Pre-validate all export infos before starting any work.
        for (_, info) in exportInfos {
            do {
                try ExportMetadataProcessor.validateExportInfo(info)
            } catch {
                AppLog.error("SongExportPresenter", "export rejected: pre-validation failed trackID=\(info.trackID) error=\(error.localizedDescription)")
                cleanupExportDirectory(cleanupDirectoryURL)
                presentExportError(
                    from: viewController,
                    message: String(localized: "Metadata validation failed for \"\(info.title ?? info.trackID)\": \(error.localizedDescription)"),
                )
                return
            }
        }
        AppLog.info("SongExportPresenter", "pre-validation passed for \(exportInfos.count) track(s)")

        let progressAlert = AlertProgressIndicatorViewController(
            title: String(localized: "Preparing"),
            message: String(localized: "Embedding metadata…"),
        )
        viewController.present(progressAlert, animated: true) {
            Task { @MainActor [weak viewController] in
                AppLog.info("SongExportPresenter", "embedExportMetadata starting count=\(exportInfos.count)")

                var firstFailure: (trackID: String, title: String, error: any Error)?
                let total = exportInfos.count

                for (index, (url, var info)) in exportInfos.enumerated() {
                    guard firstFailure == nil else { break }
                    let percent = Int(Double(index) / Double(total) * 100)
                    progressAlert.progressContext.purpose(
                        message: String(localized: "Embedding metadata…") + " \(percent)%",
                    )
                    do {
                        if info.artworkData == nil, let locations, let artworkURL = info.artworkURL {
                            info.artworkData = try? await DownloadArtworkProcessor.cachedArtworkData(
                                trackID: info.trackID,
                                artworkURL: artworkURL,
                                apiClient: apiClient,
                                locations: locations,
                                session: .shared,
                            )
                        }

                        try await ExportMetadataProcessor.embedExportMetadata(info, into: url)
                        AppLog.info("SongExportPresenter", "embedExportMetadata success trackID=\(info.trackID) file=\(url.lastPathComponent)")

                        try await ExportMetadataProcessor.verifyEmbeddedMetadata(in: url, expectedTrackID: info.trackID)
                        AppLog.info("SongExportPresenter", "verifyEmbeddedMetadata passed trackID=\(info.trackID)")

                        let donePercent = Int(Double(index + 1) / Double(total) * 100)
                        progressAlert.progressContext.purpose(
                            message: String(localized: "Embedding metadata…") + " \(donePercent)%",
                        )
                    } catch {
                        AppLog.error("SongExportPresenter", "export rejected: embed/verify failed trackID=\(info.trackID) error=\(error.localizedDescription)")
                        firstFailure = (info.trackID, info.title ?? info.trackID, error)
                    }
                }

                guard let viewController else {
                    self.cleanupExportDirectory(cleanupDirectoryURL)
                    return
                }

                if let failure = firstFailure {
                    AppLog.error("SongExportPresenter", "export aborted due to failure on trackID=\(failure.trackID)")
                    self.cleanupExportDirectory(cleanupDirectoryURL)
                    progressAlert.dismiss(animated: true) {
                        self.presentExportError(
                            from: viewController,
                            message: String(localized: "Metadata embedding failed for \"\(failure.title)\": \(failure.error.localizedDescription)"),
                        )
                    }
                    return
                }

                AppLog.info("SongExportPresenter", "embedExportMetadata all succeeded count=\(exportInfos.count)")

                progressAlert.dismiss(animated: true) {
                    self.presentShareSheet(
                        urls: urls,
                        cleanupDirectoryURL: cleanupDirectoryURL,
                        from: viewController,
                        barButtonItem: barButtonItem,
                        sourceView: sourceView,
                        sourceRect: sourceRect,
                    )
                }
            }
        }
    }
}

private extension SongExportPresenter {
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

    func makeExportURLs(for items: [SongExportItem]) -> (urls: [URL], cleanupDirectoryURL: URL?) {
        guard !items.isEmpty else {
            return ([], nil)
        }

        let fileManager = FileManager.default
        let cleanupDirectoryURL = fileManager.temporaryDirectory
            .appendingPathComponent("am-export-\(UUID().uuidString)", isDirectory: true)

        do {
            try fileManager.createDirectory(at: cleanupDirectoryURL, withIntermediateDirectories: true)
        } catch {
            AppLog.warning(self, "makeExportURLs createDirectory failed error=\(error.localizedDescription)")
            return (items.map(\.sourceURL), nil)
        }

        var urls: [URL] = []
        var usedFileNames = Set<String>()
        var createdTemporaryFile = false

        for item in items {
            let destinationURL = cleanupDirectoryURL.appendingPathComponent(
                uniqueFileName(for: item, usedFileNames: &usedFileNames),
            )

            do {
                try fileManager.linkItem(at: item.sourceURL, to: destinationURL)
                urls.append(destinationURL)
                createdTemporaryFile = true
            } catch {
                do {
                    try fileManager.copyItem(at: item.sourceURL, to: destinationURL)
                    urls.append(destinationURL)
                    createdTemporaryFile = true
                } catch {
                    AppLog.warning(self, "makeExportURLs copy fallback failed path=\(item.sourceURL.path) error=\(error.localizedDescription)")
                    urls.append(item.sourceURL)
                }
            }
        }

        guard createdTemporaryFile else {
            cleanupExportDirectory(cleanupDirectoryURL)
            return (urls, nil)
        }

        return (urls, cleanupDirectoryURL)
    }

    func uniqueFileName(for item: SongExportItem, usedFileNames: inout Set<String>) -> String {
        let fileExtension = item.sourceURL.pathExtension
        let baseName = item.preferredFileBaseName
        var candidate = fileExtension.isEmpty ? baseName : "\(baseName).\(fileExtension)"
        var suffix = 2

        while usedFileNames.contains(candidate) {
            let deduplicatedBaseName = "\(baseName) (\(suffix))"
            candidate = fileExtension.isEmpty ? deduplicatedBaseName : "\(deduplicatedBaseName).\(fileExtension)"
            suffix += 1
        }

        usedFileNames.insert(candidate)
        return candidate
    }
}
