import Foundation
import SPIndicator

enum DownloadSubmissionFeedbackPresenter {
    static func present(_ result: DownloadManager.SubmitResult) {
        var parts: [String] = []
        if result.queued > 0 {
            parts.append(String(localized: "\(result.queued) tracks queued"))
        }
        if result.skipped > 0 {
            parts.append(String(localized: "\(result.skipped) already downloaded"))
        }

        let message = parts.isEmpty
            ? String(localized: "No tracks to download.")
            : parts.joined(separator: "\n")
        SPIndicator.present(
            title: String(localized: "Download"),
            message: message,
            preset: .done
        )
    }
}
