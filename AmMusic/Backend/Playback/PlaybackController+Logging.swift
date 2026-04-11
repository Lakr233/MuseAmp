//
//  PlaybackController+Logging.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import AmMusicPlayerKit

extension PlaybackController {
    static let playerLogger: any MusicPlayerLogger = PlaybackControllerPlayerLogger()
}

private struct PlaybackControllerPlayerLogger: MusicPlayerLogger {
    func log(level: MusicPlayerLogLevel, component: String, message: String) {
        let content = "[\(component)] \(message)"
        switch level {
        case .verbose:
            AppLog.verbose(PlaybackController.self, content)
        case .info:
            AppLog.info(PlaybackController.self, content)
        case .warning:
            AppLog.warning(PlaybackController.self, content)
        case .error:
            AppLog.error(PlaybackController.self, content)
        }
    }
}
