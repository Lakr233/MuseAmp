//
//  DownloadMenuProvider.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import UIKit

enum DownloadMenuProvider {
    static func downloadAllAction(
        allDownloaded: Bool,
        onDownload: @escaping () -> Void,
    ) -> UIAction {
        guard !allDownloaded else {
            return UIAction(
                title: String(localized: "All Downloaded"),
                image: UIImage(systemName: "checkmark.circle.fill"),
                attributes: .disabled,
            ) { _ in }
        }
        return UIAction(
            title: String(localized: "Download All Songs"),
            image: UIImage(systemName: "arrow.down.circle"),
        ) { _ in
            onDownload()
        }
    }
}
