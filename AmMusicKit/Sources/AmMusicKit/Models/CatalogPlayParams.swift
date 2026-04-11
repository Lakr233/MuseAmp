//
//  CatalogPlayParams.swift
//  AmMusicKit
//
//  Created by @Lakr233 on 2026/04/11.
//

import Foundation

public struct CatalogPlayParams: Decodable, Hashable, Sendable {
    public let id: String
    public let kind: String

    public init(id: String, kind: String) {
        self.id = id
        self.kind = kind
    }
}
