//
//  AppEnvironment+Transfer.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import Foundation

extension AppEnvironment {
    func makeSyncTransferSession() -> SyncTransferSession {
        SyncTransferSession(
            paths: paths,
            libraryDatabase: libraryDatabase,
            lyricsCacheStore: lyricsCacheStore,
            audioFileImporter: audioFileImporter,
            apiClient: apiClient,
        )
    }
}
