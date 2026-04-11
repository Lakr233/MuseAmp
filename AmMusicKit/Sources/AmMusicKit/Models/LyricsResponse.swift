//
//  LyricsResponse.swift
//  AmMusicKit
//
//  Created by @Lakr233 on 2026/04/11.
//

import Foundation

public struct LyricsResponse: Decodable, Hashable, Sendable {
    public let lyrics: String

    public init(lyrics: String) {
        self.lyrics = lyrics
    }
}
