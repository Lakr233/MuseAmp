@preconcurrency import Combine
import Foundation

public final class DatabaseManager: @unchecked Sendable {
    public let paths: LibraryPaths
    public let lyricsCacheStore: LyricsCacheStore

    private let initializationLock = NSLock()

    let dependencies: RuntimeDependencies
    let logger: DatabaseLogger
    let fileManager: LibraryFileManager
    let cacheCoordinator: CacheCoordinator
    let bootstrapper: DatabaseBootstrapper
    let eventSubject: PassthroughSubject<LibraryEvent, Never>

    public nonisolated(unsafe) let events: AnyPublisher<LibraryEvent, Never>

    var indexStore: IndexStore?
    var stateStore: StateStore?
    var downloadCoordinator: DownloadCoordinator?
    var initialized = false

    public init(baseDirectory: URL? = nil, dependencies: RuntimeDependencies, logSink: LogSink? = nil) {
        paths = LibraryPaths(baseDirectory: baseDirectory, logSink: logSink)
        lyricsCacheStore = LyricsCacheStore(paths: paths, logSink: logSink)
        self.dependencies = dependencies
        logger = DatabaseLogger(sink: logSink)
        fileManager = LibraryFileManager(paths: paths, logger: logger)
        cacheCoordinator = CacheCoordinator(paths: paths, lyricsStore: lyricsCacheStore, logger: logger)
        bootstrapper = DatabaseBootstrapper(paths: paths, logger: logger)
        let subject = PassthroughSubject<LibraryEvent, Never>()
        eventSubject = subject
        events = subject.eraseToAnyPublisher()
    }

    @DatabaseActor
    public func initialize() async throws {
        try initializeSynchronously()
    }

    public func initializeSynchronously() throws {
        initializationLock.lock()
        defer { initializationLock.unlock() }

        precondition(!initialized, "DatabaseManager.initialize() must only be called once")
        let result = try bootstrapper.bootstrap()
        indexStore = result.indexStore
        stateStore = result.stateStore
        downloadCoordinator = DownloadCoordinator(stateStore: result.stateStore, logger: logger)
        initialized = true

        if let reason = result.indexResetReason {
            eventSubject.send(.indexResetStarted(reason: reason))
            eventSubject.send(.indexResetFinished(reason: reason))
        }
        eventSubject.send(.runtimeReady)
    }
}
