//
//  CatalogAlbum.swift
//  AmMusicKit
//
//  Created by @Lakr233 on 2026/04/11.
//

import Foundation

public struct CatalogAlbum: Decodable, Hashable, Sendable, Identifiable {
    public let id: String
    public let type: String
    public let href: String?
    public let attributes: CatalogAlbumAttributes
    public let relationships: CatalogAlbumRelationships?

    public init(
        id: String,
        type: String,
        href: String?,
        attributes: CatalogAlbumAttributes,
        relationships: CatalogAlbumRelationships?,
    ) {
        self.id = id
        self.type = type
        self.href = href
        self.attributes = attributes
        self.relationships = relationships
    }

    public static func == (lhs: CatalogAlbum, rhs: CatalogAlbum) -> Bool {
        lhs.id == rhs.id && lhs.type == rhs.type
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(type)
    }
}
