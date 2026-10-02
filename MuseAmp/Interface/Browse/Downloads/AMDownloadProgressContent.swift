import Foundation

struct AMDownloadProgressContent: Equatable {
    let title: String
    let subtitle: String
    let progressText: String
    let artworkURL: URL?
    let progress: Double
    let isFailed: Bool
}
