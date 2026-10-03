//
//  TVAppContext+Session.swift
//  MuseAmpTV
//
//  Created by OpenAI on 2026/04/12.
//

import Foundation
import MuseAmpDatabaseKit
import MuseAmpPlayerKit
import UIKit

extension TVAppContext {
    private static let generatedPairingCode: String = .init(format: "%06d", Int.random(in: 0 ..< 1_000_000))
    private static let generatedBonjourToken = SyncBonjourIdentity.makeToken()

    private static var advertisedReceiverDeviceName: String {
        SyncBonjourIdentity.makeAdvertisedDeviceName(
            baseName: UIDevice.current.name,
            token: generatedBonjourToken,
        )
    }

    private static var advertisedReceiverServiceName: String {
        SyncBonjourIdentity.makeAdvertisedServiceName(
            baseName: UIDevice.current.name,
            token: generatedBonjourToken,
        )
    }

    var receiverHandshakeInfo: SyncReceiverHandshakeInfo {
        SyncReceiverHandshakeInfo(
            serviceName: Self.advertisedReceiverServiceName,
            deviceName: Self.advertisedReceiverDeviceName,
            pairingCode: Self.generatedPairingCode,
        )
    }

    var pairingCode: String {
        Self.generatedPairingCode
    }

    var currentSessionDisplayName: String {
        currentSessionManifest?.playlistName ?? String(localized: "Transferred Playlist")
    }

    var currentSessionTrackCount: Int {
        currentSessionManifest?.expectedTrackCount ?? 0
    }

    func restoreSessionStateAtLaunch() async {
        switch playlistSessionStore.validate(database: libraryDatabase, paths: paths) {
        case .missing:
            currentSessionManifest = nil
            let strayTracks = allTracks()
            guard !strayTracks.isEmpty else {
                return
            }

            AppLog.warning(self, "restoreSessionStateAtLaunch clearing stray tracks count=\(strayTracks.count)")
            await clearSessionLibrary()

        case let .valid(manifest):
            currentSessionManifest = manifest
            let restored = await playbackController.restorePersistedPlaybackIfNeeded(allowAutoPlay: false)
            let didStartPlayback = restored ? true : await playCurrentSession()
            if didStartPlayback {
                playbackController.setRepeatMode(.queue)
            } else {
                setPendingSessionAlert(
                    title: String(localized: "Playback Failed"),
                    message: String(localized: "The transferred playlist is still available on Apple TV, but playback could not start automatically."),
                )
            }
            AppLog.info(
                self,
                "restoreSessionStateAtLaunch restored session id=\(manifest.sessionID) playlist='\(sanitizedLogText(manifest.playlistName))' playbackRestored=\(restored) playbackStarted=\(didStartPlayback)",
            )

        case let .invalid(message):
            setPendingSessionAlert(
                title: String(localized: "Playlist Unavailable"),
                message: message,
            )
            AppLog.warning(self, "restoreSessionStateAtLaunch invalid session message='\(sanitizedLogText(message))'")
            await clearSessionLibrary()
        }
    }

    @discardableResult
    func completeTransferredPlaylistSession(
        from manifest: SyncManifest,
        autoPlay: Bool,
    ) async -> Bool {
        guard let syncSession = manifest.session else {
            AppLog.error(self, "completeTransferredPlaylistSession missing manifest session metadata")
            setPendingSessionAlert(
                title: String(localized: "Transfer Failed"),
                message: String(localized: "The transferred playlist metadata was incomplete. Send it again from iPhone."),
            )
            await clearSessionLibrary()
            return false
        }

        let localManifest = TVPlaylistSessionManifest(
            syncSession: syncSession,
            sourceDeviceName: manifest.deviceName,
        )
        playlistSessionStore.save(localManifest)

        switch playlistSessionStore.validate(database: libraryDatabase, paths: paths) {
        case .missing:
            AppLog.error(self, "completeTransferredPlaylistSession validation unexpectedly returned missing")
            setPendingSessionAlert(
                title: String(localized: "Transfer Failed"),
                message: String(localized: "The transferred playlist could not be saved on Apple TV. Send it again from iPhone."),
            )
            await clearSessionLibrary()
            return false

        case let .invalid(message):
            AppLog.warning(self, "completeTransferredPlaylistSession validation failed message='\(sanitizedLogText(message))'")
            setPendingSessionAlert(
                title: String(localized: "Playlist Unavailable"),
                message: message,
            )
            await clearSessionLibrary()
            return false

        case let .valid(validManifest):
            currentSessionManifest = validManifest
            guard autoPlay else {
                return true
            }

            let started = await playCurrentSession()
            if !started {
                AppLog.error(self, "completeTransferredPlaylistSession failed to start playback")
                setPendingSessionAlert(
                    title: String(localized: "Playback Failed"),
                    message: String(localized: "The transferred playlist was saved, but playback could not start."),
                )
            }
            return true
        }
    }

    @discardableResult
    func playCurrentSession(shuffle: Bool = false) async -> Bool {
        let tracks = currentSessionPlaybackTracks()
        guard !tracks.isEmpty else {
            AppLog.warning(self, "playCurrentSession ignored because there are no session tracks")
            return false
        }

        let started = await playbackController.play(
            tracks: tracks,
            source: .adHoc(name: currentSessionDisplayName),
            shuffle: shuffle,
        )
        if started {
            playbackController.setRepeatMode(.queue)
        }
        return started
    }

    func currentSessionPlaybackTracks() -> [PlaybackTrack] {
        guard let manifest = currentSessionManifest else {
            return []
        }

        let tracksByID = Dictionary(uniqueKeysWithValues: allTracks().map { ($0.trackID, $0) })
        let playbackTracks = manifest.orderedTrackIDs.enumerated().compactMap { index, trackID -> PlaybackTrack? in
            guard let track = tracksByID[trackID] else {
                AppLog.warning(self, "currentSessionPlaybackTracks missing trackID=\(trackID) index=\(index)")
                return nil
            }
            return track.tvSessionPlaybackTrack(
                paths: paths,
                manifest: manifest,
                index: index,
            )
        }

        if playbackTracks.count != manifest.expectedTrackCount {
            AppLog.warning(
                self,
                "currentSessionPlaybackTracks count mismatch expected=\(manifest.expectedTrackCount) actual=\(playbackTracks.count)",
            )
        }

        return playbackTracks
    }
}

private extension AudioTrackRecord {
    func tvSessionPlaybackTrack(
        paths: LibraryPaths,
        manifest: TVPlaylistSessionManifest,
        index: Int,
    ) -> PlaybackTrack {
        let artworkFileURL = paths.artworkCacheURL(for: trackID)
        let artworkURL = FileManager.default.fileExists(atPath: artworkFileURL.path) ? artworkFileURL : nil
        let normalizedAlbumTitle = albumTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return PlaybackTrack(
            id: manifest.playbackItemIdentifier(forTrackID: trackID, index: index),
            title: title,
            artistName: artistName,
            albumName: normalizedAlbumTitle.isEmpty ? nil : normalizedAlbumTitle,
            albumID: albumID,
            artworkURL: artworkURL,
            durationInSeconds: durationSeconds > 0 ? durationSeconds : nil,
            localFileURL: paths.absoluteAudioURL(for: relativePath),
        )
    }
}
