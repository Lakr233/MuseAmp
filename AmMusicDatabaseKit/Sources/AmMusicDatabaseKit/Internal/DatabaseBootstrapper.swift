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
        try paths.ensureDirectoriesExist()

        var indexResetReason: DatabaseResetReason?
        let indexStore: IndexStore
        do {
            var candidate = try IndexStore(databaseURL: paths.indexDatabaseURL, logger: logger)
            let oldSchema = try candidate.schemaVersion()
            let oldFormat = try candidate.formatVersion()
            if oldSchema != DatabaseFormat.indexSchemaVersion || oldFormat != DatabaseFormat.indexFormatVersion {
                let reason = oldSchema == nil && oldFormat == nil
                    ? DatabaseResetReason.firstLaunch
                    : DatabaseResetReason.indexVersionMismatch(oldSchema: oldSchema, oldFormat: oldFormat)
                indexResetReason = reason
                if FileManager.default.fileExists(atPath: paths.indexDatabaseURL.path) {
                    try? FileManager.default.removeItem(at: paths.indexDatabaseURL)
                }
                candidate = try IndexStore(databaseURL: paths.indexDatabaseURL, logger: logger)
                try candidate.setSchemaVersions(
                    schema: DatabaseFormat.indexSchemaVersion,
                    format: DatabaseFormat.indexFormatVersion
                )
            }
            indexStore = candidate
        } catch {
            DBLog.critical(logger, "DatabaseBootstrapper", "index bootstrap failed error=\(error.localizedDescription)")
            throw error
        }

        let stateStore: StateStore
        do {
            let candidate = try StateStore(databaseURL: paths.stateDatabaseURL, logger: logger)
            let oldVersion = try candidate.schemaVersion()
            try candidate.migrateIfNeeded(from: oldVersion, to: DatabaseFormat.stateSchemaVersion)
            stateStore = candidate
        } catch {
            DBLog.critical(logger, "DatabaseBootstrapper", "state bootstrap failed error=\(error.localizedDescription)")
            throw error
        }

        return DatabaseBootstrapResult(
            indexStore: indexStore,
            stateStore: stateStore,
            indexResetReason: indexResetReason
        )
    }
}
