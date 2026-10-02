import Foundation

struct AMNowPlayingContent: Equatable {
    let trackID: String
    let title: String
    let subtitle: String
    let hasActiveTrack: Bool
    let routeName: String
    let routeSymbolName: String
}

extension AMNowPlayingContent {
    static let placeholder = AMNowPlayingContent(
        trackID: "",
        title: String(localized: "Nothing Playing"),
        subtitle: String(localized: "Pick a song to get started"),
        hasActiveTrack: false,
        routeName: String(localized: "iPhone"),
        routeSymbolName: "iphone",
    )
}
