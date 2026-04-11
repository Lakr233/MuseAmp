//
//  CatalogExtendedAssetURLs.swift
//  AmMusicKit
//
//  Created by @Lakr233 on 2026/04/11.
//

import Foundation

public struct CatalogExtendedAssetURLs: Decodable, Hashable, Sendable {
    public let enhancedHls: String?

    public init(enhancedHls: String?) {
        self.enhancedHls = enhancedHls
    }
}
