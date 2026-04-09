import AmMusicDatabaseKit
import AmMusicPlayerKit
import Foundation

// MARK: - Item Resolution & Session Persistence

extension PlaybackController {
    struct ResolvedPlaybackItem {
        let originalIndex: Int
        let track: PlaybackTrack
        let item: PlayerItem
    }

    func restoredCurrentIndex(
        for resolvedItems: [ResolvedPlaybackItem],
        session: PersistedPlaybackSession
    ) -> Int {
        if resolvedItems.indices.contains(session.currentIndex) {
            return session.currentIndex
        }
        if let exactMatch = resolvedItems.firstIndex(where: { $0.track.id == session.currentTrackID }) {
            return exactMatch
        }
        if let nearestPlayable = resolvedItems.firstIndex(where: { $0.originalIndex >= session.currentIndex }) {
            return nearestPlayable
        }
        return 0
    }

    func track(for item: PlayerItem?) -> PlaybackTrack? {
        guard let item else { return nil }
        if let track = queueState.trackLookup[item.id] {
            return track
        }
        return PlaybackTrack(
            id: Self.sourceTrackID(for: item.id),
            title: item.title,
            artistName: item.artist,
            albumName: item.album,
            artworkURL: item.artworkURL,
            durationInSeconds: item.durationInSeconds
        )
    }

    func preferredStartIndex(
        for resolvedItems: [ResolvedPlaybackItem],
        requestedIndex: Int
    ) -> Int {
        guard !resolvedItems.isEmpty else { return 0 }
        if let nextPlayable = resolvedItems.firstIndex(where: { $0.originalIndex >= requestedIndex }) {
            return nextPlayable
        }
        return 0
    }

    func resolvePlayableItems(for tracks: [PlaybackTrack]) async -> [ResolvedPlaybackItem] {
        let cachedItems = queueState.itemCache
        let audioDirectory = paths.audioDirectory
        let localDownloadPaths = completedDownloadPathsByTrackID()

        let resolved: [ResolvedPlaybackItem] = await withTaskGroup(of: ResolvedPlaybackItem?.self) { group in
            for (index, track) in tracks.enumerated() {
                group.addTask {
                    do {
                        let templateItem = try await Self.resolvePlayerItem(
                            for: track,
                            cachedItem: cachedItems[track.id],
                            localDownloadPath: localDownloadPaths[track.id],
                            audioDirectory: audioDirectory
                        )
                        let item = Self.makeQueuedPlayerItem(for: track, template: templateItem)
                        return ResolvedPlaybackItem(originalIndex: index, track: track, item: item)
                    } catch {
                        AppLog.error(
                            "PlaybackController",
                            "resolvePlayableItems failed trackID=\(track.id) error=\(error.localizedDescription)"
                        )
                        return nil
                    }
                }
            }

            var collected: [ResolvedPlaybackItem] = []
            for await item in group {
                if let item {
                    collected.append(item)
                }
            }
            return collected.sorted { $0.originalIndex < $1.originalIndex }
        }

        for item in resolved {
            queueState.itemCache[item.track.id] = Self.makePlayerItem(for: item.track, url: item.item.url)
        }
        return resolved
    }

    nonisolated static func makeQueuedPlayerItem(
        for track: PlaybackTrack,
        template: PlayerItem
    ) -> PlayerItem {
        PlayerItem(
            id: makeQueueItemID(for: track.id),
            url: template.url,
            title: template.title,
            artist: template.artist,
            album: template.album,
            artworkURL: template.artworkURL,
            durationInSeconds: template.durationInSeconds
        )
    }

    nonisolated static func makeQueueItemID(for trackID: String) -> String {
        "\(queueItemIDPrefix)|\(UUID().uuidString)|\(trackID)"
    }

    nonisolated static func sourceTrackID(for itemID: String) -> String {
        let prefix = "\(queueItemIDPrefix)|"
        guard itemID.hasPrefix(prefix) else {
            return itemID
        }

        let components = itemID.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
        guard components.count == 3 else {
            return itemID
        }
        return String(components[2])
    }

    func completedDownloadPathsByTrackID() -> [String: String] {
        do {
            return try database.allTrackRelativePaths()
        } catch {
            AppLog.error("PlaybackController", "completedDownloadPathsByTrackID failed: \(error)")
            return [:]
        }
    }

    static func resolvePlayerItem(
        for track: PlaybackTrack,
        cachedItem: PlayerItem?,
        localDownloadPath: String?,
        audioDirectory: URL
    ) async throws -> PlayerItem {
        if let localFileURL = track.localFileURL,
           FileManager.default.fileExists(atPath: localFileURL.path)
        {
            return makePlayerItem(for: track, url: localFileURL)
        }

        if let localDownloadPath {
            let fileURL = audioDirectory.appendingPathComponent(localDownloadPath, isDirectory: false)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                return makePlayerItem(for: track, url: fileURL)
            }
        }

        if let cachedItem,
           cachedItem.url.isFileURL,
           FileManager.default.fileExists(atPath: cachedItem.url.path)
        {
            return cachedItem
        }

        throw PlaybackResolutionError.localFileUnavailable(track.id)
    }

    static func makePlayerItem(
        for track: PlaybackTrack,
        url: URL
    ) -> PlayerItem {
        PlayerItem(
            id: track.id,
            url: url,
            title: track.title,
            artist: track.artistName,
            album: track.albumName ?? "",
            artworkURL: track.artworkURL,
            durationInSeconds: track.durationInSeconds
        )
    }

    // MARK: - Session Persistence

    func makePersistedSession() -> PersistedPlaybackSession? {
        let queue = player.queue
        let orderedTracks = queue.orderedItems.compactMap(track(for:))
        guard !orderedTracks.isEmpty,
              let currentTrack = track(for: queue.nowPlaying)
        else {
            return nil
        }

        let currentIndex = queue.currentIndex
            ?? orderedTracks.firstIndex(where: { $0.id == currentTrack.id })
            ?? 0

        return PersistedPlaybackSession(
            queue: orderedTracks.map(makePersistedTrack),
            currentTrackID: currentTrack.id,
            currentIndex: currentIndex,
            currentTime: latestSnapshot.currentTime,
            shuffled: latestSnapshot.shuffled,
            repeatMode: latestSnapshot.repeatMode,
            source: latestSnapshot.source,
            shouldResumePlayback: latestSnapshot.state == .playing || latestSnapshot.state == .buffering
        )
    }

    func makePersistedTrack(from track: PlaybackTrack) -> PersistedPlaybackTrack {
        PersistedPlaybackTrack(
            id: track.id,
            title: track.title,
            artistName: track.artistName,
            albumName: track.albumName,
            albumID: track.albumID,
            artworkURL: persistedArtworkURLString(for: track),
            durationInSeconds: track.durationInSeconds,
            localRelativePath: localRelativePath(for: track)
        )
    }

    func persistedArtworkURLString(for track: PlaybackTrack) -> String? {
        guard let artworkURL = track.artworkURL else {
            return nil
        }

        guard artworkURL.isFileURL == false else {
            return nil
        }

        return artworkURL.absoluteString
    }

    func restoredArtworkURL(
        for persistedTrack: PersistedPlaybackTrack,
        localFileURL: URL?
    ) async -> URL? {
        if let artworkURLString = persistedTrack.artworkURL,
           let artworkURL = URL(string: artworkURLString),
           artworkURL.isFileURL == false
        {
            return artworkURL
        }

        let localArtworkURL = paths.artworkCacheURL(for: persistedTrack.id)
        if FileManager.default.fileExists(atPath: localArtworkURL.path) {
            return localArtworkURL
        }

        if let rebuiltArtworkURL = await rebuildLocalArtworkIfNeeded(
            forTrackID: persistedTrack.id,
            localFileURL: localFileURL,
            artworkURL: localArtworkURL
        ) {
            return rebuiltArtworkURL
        }

        guard let artworkURLString = persistedTrack.artworkURL,
              let artworkURL = URL(string: artworkURLString),
              artworkURL.isFileURL
        else {
            return nil
        }

        guard FileManager.default.fileExists(atPath: artworkURL.path) else {
            AppLog.warning(
                self,
                "restorePersistedPlayback ignored stale local artwork trackID=\(persistedTrack.id) path=\(artworkURL.path)"
            )
            return nil
        }

        return artworkURL
    }

    func rebuildLocalArtworkIfNeeded(
        forTrackID trackID: String,
        localFileURL: URL?,
        artworkURL: URL
    ) async -> URL? {
        guard let localFileURL,
              FileManager.default.fileExists(atPath: localFileURL.path)
        else {
            return nil
        }

        guard let artworkData = await metadataReader.extractArtwork(from: localFileURL) else {
            return nil
        }

        do {
            try FileManager.default.createDirectory(
                at: artworkURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
            try artworkData.write(to: artworkURL, options: .atomic)
            AppLog.info(self, "restorePersistedPlayback rebuilt local artwork trackID=\(trackID)")
            return artworkURL
        } catch {
            AppLog.error(
                self,
                "restorePersistedPlayback rebuild local artwork failed trackID=\(trackID) error=\(error.localizedDescription)"
            )
            return nil
        }
    }

    func localRelativePath(for track: PlaybackTrack) -> String? {
        if let localFileURL = track.localFileURL,
           let relativePath = relativeAudioPath(for: localFileURL)
        {
            return relativePath
        }
        return completedDownloadPathsByTrackID()[track.id]
    }

    func relativeAudioPath(for fileURL: URL) -> String? {
        let standardizedAudioDirectory = paths.audioDirectory.standardizedFileURL.path
        let standardizedFilePath = fileURL.standardizedFileURL.path
        guard standardizedFilePath == standardizedAudioDirectory
            || standardizedFilePath.hasPrefix(standardizedAudioDirectory + "/")
        else {
            return nil
        }
        return paths.relativeAudioPath(for: fileURL)
    }
}

private enum PlaybackResolutionError: LocalizedError {
    case localFileUnavailable(String)

    var errorDescription: String? {
        switch self {
        case let .localFileUnavailable(trackID):
            "Local playback file unavailable for trackID=\(trackID)"
        }
    }
}
