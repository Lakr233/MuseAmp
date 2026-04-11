//
//  IndexMetaRow.swift
//  AmMusicDatabaseKit
//
//  Created by @Lakr233 on 2026/04/11.
//

import Foundation
@preconcurrency import WCDBSwift

struct IndexMetaRow: Codable, TableCodable {
    static let tableName = "index_meta"

    var key: String
    var value: String

    enum CodingKeys: String, CodingTableKey {
        typealias Root = IndexMetaRow

        static let objectRelationalMapping = TableBinding(CodingKeys.self) {
            BindColumnConstraint(key, isPrimary: true, isNotNull: true, isUnique: true)
            BindColumnConstraint(value, isNotNull: true, defaultTo: "")
        }

        case key
        case value
    }
}
