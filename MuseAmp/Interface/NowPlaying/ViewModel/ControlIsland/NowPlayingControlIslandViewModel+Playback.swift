//
//  NowPlayingControlIslandViewModel+Playback.swift
//  MuseAmp
//
//  Created by @Lakr233 on 2026/04/11.
//

import Foundation
import MuseAmpPlayerKit

extension NowPlayingControlIslandViewModel {
    @discardableResult
    func apply(snapshot: PlaybackSnapshot) -> Presentation {
        let previousContent = content
        let content = NowPlayingContentMapper.makeContent(from: snapshot)
        self.content = content

        return Presentation(
            content: content,
            backgroundSource: NowPlayingContentMapper.makeBackgroundSource(from: snapshot),
            shouldAnimateTransition: previousContent.trackID != content.trackID,
        )
    }
}
