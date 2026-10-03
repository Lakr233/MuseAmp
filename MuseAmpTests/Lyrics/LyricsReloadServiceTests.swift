@preconcurrency import AVFoundation
import Foundation
@testable import MuseAmp
import MuseAmpDatabaseKit
import Testing
import UIKit

@Suite(.serialized)
struct LyricsReloadServiceTests {
    private func makeAPIClient() throws -> APIClient {
        try APIClient(baseURL: #require(URL(string: "https://example.com")))
    }

    @Test
    func `reload offloads embedded lyrics from the downloaded file`() async throws {
        let sandbox = TestLibrarySandbox()
        let database = try sandbox.makeDatabase()
        let paths = database.paths
        let store = LyricsCacheStore(paths: paths)
        let apiClient = try makeAPIClient()

        let ingested = try await sandbox.ingestTrack(
            makeMockTrack(trackID: "1692905594"),
            into: database,
        )
        let fileURL = paths.absoluteAudioURL(for: ingested.relativePath)
        let embeddedLyrics = "[00:01.00]Line one\n[00:05.00]Line two"
        try await ExportMetadataProcessor.embedExportMetadata(
            ExportMetadataProcessor.ExportInfo(
                trackID: "1692905594",
                albumID: "1692905593",
                artworkURL: nil,
                lyrics: embeddedLyrics,
                title: ingested.title,
                artistName: ingested.artistName,
                albumName: ingested.albumTitle,
            ),
            into: fileURL,
        )

        let service = LyricsReloadService(
            apiClient: apiClient,
            lyricsCacheStore: store,
            database: database,
            paths: paths,
        )

        let expectation = NotificationExpectation(name: .lyricsDidUpdate)

        let result = try await service.reloadLyrics(for: ingested.trackID)

        #expect(result == embeddedLyrics)
        #expect(store.lyrics(for: ingested.trackID) == embeddedLyrics)

        let notification = try #require(expectation.receivedNotification)
        let payload = notification.userInfo?[AppNotificationUserInfoKey.trackIDs] as? [String]
        #expect(payload == [ingested.trackID])
    }

    @Test
    func `reload overwrites stale cache when file embeds fresher lyrics`() async throws {
        let sandbox = TestLibrarySandbox()
        let database = try sandbox.makeDatabase()
        let paths = database.paths
        let store = LyricsCacheStore(paths: paths)
        let apiClient = try makeAPIClient()

        let ingested = try await sandbox.ingestTrack(
            makeMockTrack(trackID: "1692905595"),
            into: database,
        )
        let fileURL = paths.absoluteAudioURL(for: ingested.relativePath)
        let freshLyrics = "[00:10.00]Fresh line"
        try await ExportMetadataProcessor.embedExportMetadata(
            ExportMetadataProcessor.ExportInfo(
                trackID: "1692905595",
                albumID: "1692905593",
                artworkURL: nil,
                lyrics: freshLyrics,
                title: ingested.title,
                artistName: ingested.artistName,
                albumName: ingested.albumTitle,
            ),
            into: fileURL,
        )

        try store.saveLyrics("[00:00.00]Stale line", for: ingested.trackID)

        let service = LyricsReloadService(
            apiClient: apiClient,
            lyricsCacheStore: store,
            database: database,
            paths: paths,
        )

        _ = try await service.reloadLyrics(for: ingested.trackID)

        #expect(store.lyrics(for: ingested.trackID) == freshLyrics)
    }

    @Test
    func `rebuild keeps cached lyrics when the server cannot be reached`() async throws {
        let sandbox = TestLibrarySandbox()
        let database = try sandbox.makeDatabase()
        let paths = database.paths
        let store = LyricsCacheStore(paths: paths)
        let ingested = try await sandbox.ingestTrack(makeMockTrack(trackID: "1692905611"), into: database)
        let cachedLyrics = "[00:02.00]Cached line"
        try store.saveLyrics(cachedLyrics, for: ingested.trackID)

        let service = try LyricsReloadService(
            apiClient: makeAPIClient(),
            lyricsCacheStore: store,
            database: database,
            paths: paths,
        )
        let result = try await service.rebuildAllLyricsIndex()

        #expect(result.tracksFailed == 1)
        #expect(store.lyrics(for: ingested.trackID) == cachedLyrics)
    }

    @Test
    func `rebuild caches embedded lyrics when the server cannot be reached`() async throws {
        let sandbox = TestLibrarySandbox()
        let database = try sandbox.makeDatabase()
        let paths = database.paths
        let store = LyricsCacheStore(paths: paths)
        let ingested = try await sandbox.ingestTrack(makeMockTrack(trackID: "1692905612"), into: database)
        let embeddedLyrics = "[00:03.00]Embedded line"
        try await embedLyrics(embeddedLyrics, into: ingested, paths: paths)
        try? store.removeLyrics(for: ingested.trackID)

        let service = try LyricsReloadService(
            apiClient: makeAPIClient(),
            lyricsCacheStore: store,
            database: database,
            paths: paths,
        )
        _ = try await service.rebuildAllLyricsIndex()

        #expect(store.lyrics(for: ingested.trackID) == embeddedLyrics)
    }

    @Test
    func `rebuild keeps the embedded lyrics when the server replies with none`() async throws {
        let sandbox = TestLibrarySandbox()
        let database = try sandbox.makeDatabase()
        let paths = database.paths
        let store = LyricsCacheStore(paths: paths)
        let ingested = try await sandbox.ingestTrack(makeMockTrack(trackID: "1692905614"), into: database)
        let fileURL = paths.absoluteAudioURL(for: ingested.relativePath)
        let embeddedLyrics = "[00:04.00]Embedded line kept"
        try await embedLyrics(embeddedLyrics, into: ingested, paths: paths)
        try? store.removeLyrics(for: ingested.trackID)
        let server = LyricsServerStub(trackIDs: [ingested.trackID], reply: LyricsServerStub.emptyLyricsReply)

        let service = LyricsReloadService(
            apiClient: server.makeAPIClient(),
            lyricsCacheStore: store,
            database: database,
            paths: paths,
        )
        let result = try await service.rebuildAllLyricsIndex()

        #expect(server.requestCount == 1)
        #expect(result.tracksFailed == 0)
        #expect(await EmbeddedLyricsReader.lyrics(fromFileAt: fileURL) == embeddedLyrics)
        #expect(store.lyrics(for: ingested.trackID) == embeddedLyrics)
    }

    @Test
    func `forced reload asks the server again instead of reusing its earlier reply`() async throws {
        let sandbox = TestLibrarySandbox()
        let database = try sandbox.makeDatabase()
        let paths = database.paths
        let store = LyricsCacheStore(paths: paths)
        let ingested = try await sandbox.ingestTrack(makeMockTrack(trackID: "1692905615"), into: database)
        let server = try LyricsServerStub(
            trackIDs: [ingested.trackID],
            reply: LyricsServerStub.lyricsReply("[00:01.00]Old server line"),
        )
        let apiClient = server.makeAPIClient()
        _ = try await apiClient.lyrics(id: ingested.trackID)

        let newLyrics = "[00:01.00]New server line"
        try server.setReply(LyricsServerStub.lyricsReply(newLyrics))
        let service = LyricsReloadService(
            apiClient: apiClient,
            lyricsCacheStore: store,
            database: database,
            paths: paths,
        )
        let result = try await service.reloadLyrics(for: ingested.trackID, forceRemoteFetch: true)

        #expect(server.requestCount == 2)
        #expect(result == newLyrics)
        #expect(store.lyrics(for: ingested.trackID) == newLyrics)
    }

    @Test
    func `rebuild removes cached lyrics of songs no longer in the library`() async throws {
        let sandbox = TestLibrarySandbox()
        let database = try sandbox.makeDatabase()
        let paths = database.paths
        let store = LyricsCacheStore(paths: paths)
        try await sandbox.ingestTrack(makeMockTrack(trackID: "1692905613"), into: database)
        try store.saveLyrics("[00:01.00]Orphan", for: "1692905699")

        let service = try LyricsReloadService(
            apiClient: makeAPIClient(),
            lyricsCacheStore: store,
            database: database,
            paths: paths,
        )
        _ = try await service.rebuildAllLyricsIndex()

        #expect(!FileManager.default.fileExists(atPath: paths.lyricsCacheURL(for: "1692905699").path))
    }

    @MainActor
    @Test
    func `makeReloadLyricsAction appears only when a presenter is configured`() {
        let providerWithout = SongContextMenuProvider()
        let entry = PlaylistEntry(
            trackID: "1692905596",
            title: "Song",
            artistName: "Artist",
        )
        let menu = providerWithout.menu(for: entry, context: .library)
        let titles = collectMenuActionTitles(menu)
        #expect(!titles.contains(String(localized: "Reload Lyrics")))
    }
}

private final class NotificationExpectation: @unchecked Sendable {
    private final class Storage: @unchecked Sendable {
        let lock = NSLock()
        var received: Notification?
    }

    private let storage = Storage()
    private let observer: NSObjectProtocol

    var receivedNotification: Notification? {
        storage.lock.lock()
        defer { storage.lock.unlock() }
        return storage.received
    }

    init(name: Notification.Name) {
        let storageRef = storage
        observer = NotificationCenter.default.addObserver(
            forName: name,
            object: nil,
            queue: .main,
        ) { notification in
            storageRef.lock.lock()
            storageRef.received = notification
            storageRef.lock.unlock()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(observer)
    }
}

@MainActor
private func collectMenuActionTitles(_ menu: UIMenu?) -> [String] {
    guard let menu else { return [] }
    var titles: [String] = []
    for element in menu.children {
        if let action = element as? UIAction {
            titles.append(action.title)
        } else if let submenu = element as? UIMenu {
            titles.append(contentsOf: collectMenuActionTitles(submenu))
        }
    }
    return titles
}
