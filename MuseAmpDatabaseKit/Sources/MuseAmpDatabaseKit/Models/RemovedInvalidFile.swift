//
//  RemovedInvalidFile.swift
//  MuseAmpDatabaseKit
//
//  Created by @Lakr233 on 2026/08/01.
//

import Foundation

/// A file the rebuild identified as invalid or unreadable, enriched with the
/// indexed metadata that was available before the row was dropped so the app
/// can show the user which songs were affected.
public struct RemovedInvalidFile: Sendable, Hashable {
    public let relativePath: String
    public let trackID: String?
    public let title: String?
    public let artistName: String?
    public let reason: String

    public init(
        relativePath: String,
        trackID: String?,
        title: String?,
        artistName: String?,
        reason: String,
    ) {
        self.relativePath = relativePath
        self.trackID = trackID
        self.title = title
        self.artistName = artistName
        self.reason = reason
    }
}
