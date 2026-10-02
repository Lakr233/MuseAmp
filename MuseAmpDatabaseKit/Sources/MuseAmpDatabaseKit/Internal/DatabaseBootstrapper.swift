//
//  DatabaseBootstrapper.swift
//  MuseAmpDatabaseKit
//
//  Created by @Lakr233 on 2026/04/11.
//

import Foundation

struct DatabaseBootstrapResult {
    let indexStore: IndexStore
    let stateStore: StateStore
}

struct DatabaseBootstrapper {
    let paths: LibraryPaths
    let logger: DatabaseLogger

    func bootstrap() throws -> DatabaseBootstrapResult {
        logger.info("DatabaseBootstrapper", "bootstrap started baseDirectory=\(paths.baseDirectory.path)")
        try paths.ensureDirectoriesExist()

        let indexStore: IndexStore
        do {
            let indexFileExists = FileManager.default.fileExists(atPath: paths.indexDatabaseURL.path)
            logger.info("DatabaseBootstrapper", "index database path=\(paths.indexDatabaseURL.path) exists=\(indexFileExists)")
            let candidate = try IndexStore(databaseURL: paths.indexDatabaseURL, logger: logger)
            let oldSchema = try candidate.schemaVersion()
            let oldFormat = try candidate.formatVersion()
            let trackCount = (try? candidate.allTracks().count) ?? -1
            logger.info("DatabaseBootstrapper", "index database opened schema=\(oldSchema.map(String.init) ?? "nil") format=\(oldFormat.map(String.init) ?? "nil") tracks=\(trackCount)")
            if oldSchema != DatabaseFormat.indexSchemaVersion || oldFormat != DatabaseFormat.indexFormatVersion {
                logger.info("DatabaseBootstrapper", "index schema stamp needed expected=\(DatabaseFormat.indexSchemaVersion)/\(DatabaseFormat.indexFormatVersion)")
                try candidate.setSchemaVersions(
                    schema: DatabaseFormat.indexSchemaVersion,
                    format: DatabaseFormat.indexFormatVersion,
                )
            }
            indexStore = candidate
        } catch {
            logger.critical("DatabaseBootstrapper", "index bootstrap failed error=\(error.localizedDescription)")
            throw error
        }

        let stateStore: StateStore
        do {
            let stateFileExists = FileManager.default.fileExists(atPath: paths.stateDatabaseURL.path)
            logger.info("DatabaseBootstrapper", "state database path=\(paths.stateDatabaseURL.path) exists=\(stateFileExists)")
            let candidate = try StateStore(databaseURL: paths.stateDatabaseURL)
            let oldVersion = try candidate.schemaVersion()
            logger.info("DatabaseBootstrapper", "state database opened schema=\(oldVersion.map(String.init) ?? "nil")")
            try candidate.migrateIfNeeded(from: oldVersion, to: DatabaseFormat.stateSchemaVersion)
            stateStore = candidate
        } catch {
            logger.critical("DatabaseBootstrapper", "state bootstrap failed error=\(error.localizedDescription)")
            throw error
        }

        logger.info("DatabaseBootstrapper", "bootstrap completed")
        return DatabaseBootstrapResult(
            indexStore: indexStore,
            stateStore: stateStore,
        )
    }
}
