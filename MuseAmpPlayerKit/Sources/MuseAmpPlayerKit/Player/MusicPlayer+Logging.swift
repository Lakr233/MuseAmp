//
//  MusicPlayer+Logging.swift
//  MuseAmpPlayerKit
//
//  Created by @Lakr233 on 2026/04/11.
//

extension MusicPlayer {
    func log(
        _ level: MusicPlayerLogLevel,
        _ message: @autoclosure () -> String,
    ) {
        logger.log(level: level, component: "MusicPlayer", message: message())
    }

    func describe(item: PlayerItem?) -> String {
        guard let item else { return "nil" }
        return "\(item.id) | \(item.title) | \(item.artist)"
    }

    func describe(queue snapshot: QueueSnapshot) -> String {
        "history=\(snapshot.history.count) current=\(describe(item: snapshot.nowPlaying)) upcoming=\(snapshot.upcoming.count) total=\(snapshot.totalCount) shuffled=\(snapshot.shuffled) repeat=\(snapshot.repeatMode)"
    }
}
