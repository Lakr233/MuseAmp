//
//  SearchResponse.swift
//  AmMusicKit
//
//  Created by @Lakr233 on 2026/04/11.
//

import Foundation

public struct SearchResponse: Decodable, Sendable {
    public let results: SearchResults

    public init(results: SearchResults) {
        self.results = results
    }
}
