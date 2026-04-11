//
//  DatabaseBootstrapper.swift
//  AmMusicDatabaseKit
//
//  Created by @Lakr233 on 2026/04/11.
//

import Foundation

struct DatabaseBootstrapResult {
    let indexStore: IndexStore
    let stateStore: StateStore
    let indexResetReason: DatabaseResetReason?
}

struct DatabaseBootstrapper {
    let paths: LibraryPaths
    let logger: DatabaseLogger

    func bootstrap() throws -> DatabaseBootstrapResult {
        DBLog.info(logger, "DatabaseBootstrapper", "bootstrap started baseDirectory=\(paths.baseDirectory.path)")
        try paths.ensureDirectoriesExist()

        let indexStore: IndexStore
        do {
            let indexFileExists = FileManager.default.fileExists(atPath: paths.indexDatabaseURL.path)
            DBLog.info(logger, "DatabaseBootstrapper", "index database path=\(paths.indexDatabaseURL.path) exists=\(indexFileExists)")
            let candidate = try IndexStore(databaseURL: paths.indexDatabaseURL, logger: logger)
            let oldSchema = try candidate.schemaVersion()
            let oldFormat = try candidate.formatVersion()
            let trackCount = (try? candidate.allTracks().count) ?? -1
            DBLog.info(logger, "DatabaseBootstrapper", "index database opened schema=\(oldSchema.map(String.init) ?? "nil") format=\(oldFormat.map(String.init) ?? "nil") tracks=\(trackCount)")
            if oldSchema != DatabaseFormat.indexSchemaVersion || oldFormat != DatabaseFormat.indexFormatVersion {
                DBLog.info(logger, "DatabaseBootstrapper", "index schema stamp needed expected=\(DatabaseFormat.indexSchemaVersion)/\(DatabaseFormat.indexFormatVersion)")
                try candidate.setSchemaVersions(
                    schema: DatabaseFormat.indexSchemaVersion,
                    format: DatabaseFormat.indexFormatVersion,
                )
            }
            indexStore = candidate
        } catch {
            DBLog.critical(logger, "DatabaseBootstrapper", "index bootstrap failed error=\(error.localizedDescription)")
            throw error
        }

        let stateStore: StateStore
        do {
            let stateFileExists = FileManager.default.fileExists(atPath: paths.stateDatabaseURL.path)
            DBLog.info(logger, "DatabaseBootstrapper", "state database path=\(paths.stateDatabaseURL.path) exists=\(stateFileExists)")
            let candidate = try StateStore(databaseURL: paths.stateDatabaseURL, logger: logger)
            let oldVersion = try candidate.schemaVersion()
            DBLog.info(logger, "DatabaseBootstrapper", "state database opened schema=\(oldVersion.map(String.init) ?? "nil")")
            try candidate.migrateIfNeeded(from: oldVersion, to: DatabaseFormat.stateSchemaVersion)
            stateStore = candidate
        } catch {
            DBLog.critical(logger, "DatabaseBootstrapper", "state bootstrap failed error=\(error.localizedDescription)")
            throw error
        }

        DBLog.info(logger, "DatabaseBootstrapper", "bootstrap completed")
        return DatabaseBootstrapResult(
            indexStore: indexStore,
            stateStore: stateStore,
            indexResetReason: nil,
        )
    }
}
