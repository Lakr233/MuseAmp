//
//  SongResponse.swift
//  AmMusicKit
//
//  Created by @Lakr233 on 2026/04/11.
//

import Foundation

public struct SongResponse: Decodable, Sendable {
    public let href: String?
    public let next: String?
    public let data: [CatalogSong]

    public init(href: String?, next: String?, data: [CatalogSong]) {
        self.href = href
        self.next = next
        self.data = data
    }

    public var firstSong: CatalogSong? {
        data.first
    }
}
