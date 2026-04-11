//
//  CatalogArtist.swift
//  AmMusicKit
//
//  Created by @Lakr233 on 2026/04/11.
//

import Foundation

public struct CatalogArtist: Decodable, Hashable, Sendable {
    public let id: String
    public let type: String
    public let href: String?
    public let attributes: CatalogArtistAttributes

    public init(id: String, type: String, href: String?, attributes: CatalogArtistAttributes) {
        self.id = id
        self.type = type
        self.href = href
        self.attributes = attributes
    }

    public static func == (lhs: CatalogArtist, rhs: CatalogArtist) -> Bool {
        lhs.id == rhs.id && lhs.type == rhs.type
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(type)
    }
}
