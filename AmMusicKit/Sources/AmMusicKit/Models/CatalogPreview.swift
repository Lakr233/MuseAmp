//
//  CatalogPreview.swift
//  AmMusicKit
//
//  Created by @Lakr233 on 2026/04/11.
//

import Foundation

public struct CatalogPreview: Decodable, Hashable, Sendable {
    public let url: String

    public init(url: String) {
        self.url = url
    }
}
