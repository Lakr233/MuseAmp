//
//  ResourceList.swift
//  AmMusicKit
//
//  Created by @Lakr233 on 2026/04/11.
//

import Foundation

public struct ResourceList<Resource: Decodable & Sendable>: Decodable, Sendable {
    public let href: String?
    public let next: String?
    public let data: [Resource]

    private enum CodingKeys: String, CodingKey {
        case href
        case next
        case data
    }

    public init(href: String?, next: String?, data: [Resource]) {
        self.href = href
        self.next = next
        self.data = data
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        href = try container.decodeIfPresent(String.self, forKey: .href)
        next = try container.decodeIfPresent(String.self, forKey: .next)
        data = try container.decodeIfPresent([Resource].self, forKey: .data) ?? []
    }
}
