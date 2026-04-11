//
//  StateMetaRow.swift
//  AmMusicDatabaseKit
//
//  Created by @Lakr233 on 2026/04/11.
//

import Foundation
@preconcurrency import WCDBSwift

struct StateMetaRow: Codable, TableCodable {
    static let tableName = "state_meta"

    var key: String
    var value: String

    enum CodingKeys: String, CodingTableKey {
        typealias Root = StateMetaRow

        static let objectRelationalMapping = TableBinding(CodingKeys.self) {
            BindColumnConstraint(key, isPrimary: true, isNotNull: true, isUnique: true)
            BindColumnConstraint(value, isNotNull: true, defaultTo: "")
        }

        case key
        case value
    }
}
