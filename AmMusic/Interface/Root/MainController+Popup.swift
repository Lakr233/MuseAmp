//
//  MainController+Popup.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import AmMusicDatabaseKit
import AmMusicPlayerKit
import Combine
import ConfigurableKit
import Kingfisher
import LNPopupController
import UIKit

// MARK: - Popup Management for Relaxed/Catalyst Mode

extension MainController {
    func bindPlaybackPopup() {
        guard currentLayoutMode != .compact else { return }

        configureContentContainerPopupBar()
        prepareNowPlayingPopupContent()

        ConfigurableKit.publisher(
            forKey: AppPreferences.cleanSongTitleKey, type: Bool.self,
        )
        .dropFirst()
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
            guard let self else { return }
            updateNowPlayingPopupItem(using: environment.playbackController.snapshot)
        }
        .store(in: &cancellables)

        environment.playbackController.$snapshot
            .removeDuplicates { lhs, rhs in
                lhs.currentTrack == rhs.currentTrack
                    && lhs.state == rhs.state
                    && lhs.upcoming == rhs.upcoming
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in
                self?.syncPopupPresentation(with: snapshot)
            }
            .store(in: &cancellables)

        environment.playbackController.$snapshot
            .removeDuplicates { lhs, rhs in
                lhs.currentTime == rhs.currentTime
                    && lhs.duration == rhs.duration
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in
                self?.updatePopupProgress(using: snapshot)
            }
            .store(in: &cancellables)

        environment.playbackController.playbackTimeSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] currentTime, duration in
                guard let self else { return }
                let snapshot = environment.playbackController.latestSnapshot
                    .withTime(currentTime, duration: duration)
                updatePopupProgress(using: snapshot)
            }
            .store(in: &cancellables)
    }

    func unbindPlaybackPopup() {
        cancellables.removeAll()
        popupArtworkTask?.cancel()
        popupArtworkTask = nil

        if contentContainerController.popupPresentationState != .barHidden {
            contentContainerController.dismissPopupBar(animated: false)
        }
    }

    private func configureContentContainerPopupBar() {
        let bar = contentContainerController.popupBar
        bar.customBarViewController = nil
        bar.barStyle = .floating
        bar.progressViewStyle = .bottom
        bar.usesContentControllersAsDataSource = false
        bar.dataSource = self
        bar.delegate = self

        bar.addInteraction(UIContextMenuInteraction(delegate: self))

        contentContainerController.popupInteractionStyle = .drag
        contentContainerController.popupPresentationDelegate = self
    }

    private func prepareNowPlayingPopupContent() {
        let vc = makeNowPlayingPopupContentVC()
        vc.loadViewIfNeeded()
        updateNowPlayingPopupItem(using: environment.playbackController.snapshot)
    }

    // MARK: - Sync

    private func syncPopupPresentation(with snapshot: PlaybackSnapshot) {
        guard currentLayoutMode != .compact else { return }
        guard !isPagingCooldownActive else {
            updatePopupProgress(using: snapshot)
            return
        }

        updateNowPlayingPopupItem(using: snapshot)

        let isInitialPresentation = contentContainerController.popupPresentationState == .barHidden
        ensurePopupPresented(openFullscreen: false, animated: !isInitialPresentation)
    }

    private var isPagingCooldownActive: Bool {
        popupPagingHandler.isCooldownActive
    }

    private func ensurePopupPresented(openFullscreen: Bool, animated: Bool) {
        let vc = makeNowPlayingPopupContentVC()
        updateNowPlayingPopupItem(using: environment.playbackController.snapshot)

        let container = contentContainerController
        if container.popupPresentationState == .barHidden || container.popupContent !== vc {
            container.presentPopupBar(with: vc, openPopup: openFullscreen, animated: animated)
            return
        }

        guard openFullscreen, container.popupPresentationState != .open else { return }
        container.openPopup(animated: animated)
    }

    // MARK: - Now Playing VC

    private func makeNowPlayingPopupContentVC() -> NowPlayingRelaxedController {
        if let existing = nowPlayingPopupContentViewController {
            return existing
        }
        let controller = NowPlayingRelaxedController(environment: environment)
        controller.title = String(localized: "Now Playing")
        nowPlayingPopupContentViewController = controller
        return controller
    }

    // MARK: - Popup Item Updates

    func updateNowPlayingPopupItem(using snapshot: PlaybackSnapshot) {
        _ = makeNowPlayingPopupContentVC()

        let bar = contentContainerController.popupBar
        let popupItem: LNPopupItem
        if let existing = bar.popupItem {
            popupItem = existing
        } else {
            popupItem = LNPopupItem()
            bar.popupItem = popupItem
        }

        popupItem.barButtonItems = [popupPlayPauseItem, popupNextItem]

        if let currentTrack = snapshot.currentTrack {
            let sanitizedTitle = currentTrack.title.sanitizedTrackTitle
            if popupItem.title != sanitizedTitle {
                popupItem.title = sanitizedTitle
            }
            if popupItem.subtitle != currentTrack.artistName {
                popupItem.subtitle = currentTrack.artistName
            }
            updatePopupBarButtonState(using: snapshot)
            popupItem.progress = Float(popupProgress(for: snapshot))
            popupItem.accessibilityProgressLabel = String(localized: "Playback Progress")
            popupItem.accessibilityProgressValue = "\(formattedPlaybackTime(snapshot.currentTime)) / \(formattedPlaybackTime(snapshot.duration))"
            popupItem.userInfo = [
                "trackID": currentTrack.id,
                "queueIndex": snapshot.playerIndex as Any,
            ]
            updatePopupArtwork(for: currentTrack.artworkURL, popupItem: popupItem)
        } else {
            popupItem.title = String(localized: "Nothing Playing")
            popupItem.subtitle = nil
            popupPlayPauseItem.image = UIImage(systemName: "play.fill")
            popupPlayPauseItem.isEnabled = false
            popupNextItem.isEnabled = false
            popupItem.progress = 0
            popupItem.accessibilityProgressValue = nil
            popupItem.userInfo = nil
            updatePopupArtwork(for: nil, popupItem: popupItem)
        }
    }

    private func updatePopupProgress(using snapshot: PlaybackSnapshot) {
        guard currentLayoutMode != .compact else { return }
        let bar = contentContainerController.popupBar
        guard let popupItem = bar.popupItem, snapshot.currentTrack != nil else { return }
        popupItem.progress = Float(popupProgress(for: snapshot))
        popupItem.accessibilityProgressValue = "\(formattedPlaybackTime(snapshot.currentTime)) / \(formattedPlaybackTime(snapshot.duration))"
    }

    private func popupProgress(for snapshot: PlaybackSnapshot) -> Double {
        guard snapshot.duration > 0 else { return 0 }
        return min(max(snapshot.currentTime / snapshot.duration, 0), 1)
    }

    // MARK: - Button Items

    private func updatePopupBarButtonState(using snapshot: PlaybackSnapshot) {
        popupPlayPauseItem.image = UIImage(systemName: snapshot.state == .playing ? "pause.fill" : "play.fill")
        popupPlayPauseItem.isEnabled = true
        popupNextItem.isEnabled = !snapshot.upcoming.isEmpty || snapshot.repeatMode != .off
    }

    // MARK: - Artwork

    private static let placeholderArtwork: UIImage = Bundle.appIcon

    private func updatePopupArtwork(for artworkURL: URL?, popupItem: LNPopupItem) {
        if artworkURL == popupArtworkURL,
           popupItem.image != nil || popupArtworkTask != nil
        {
            return
        }

        popupArtworkTask?.cancel()
        popupArtworkTask = nil
        popupArtworkURL = artworkURL

        guard let artworkURL else {
            popupItem.image = Self.placeholderArtwork
            return
        }

        if artworkURL.isFileURL {
            let image = UIImage(contentsOfFile: artworkURL.path)
            if image == nil {
                AppLog.warning(self, "updatePopupArtwork missing local artwork path=\(artworkURL.path)")
            }
            popupItem.image = image ?? Self.placeholderArtwork
            return
        }

        popupItem.image = Self.placeholderArtwork

        popupArtworkTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let image = await retrievePopupArtwork(from: artworkURL)
            popupArtworkTask = nil
            guard !Task.isCancelled,
                  popupArtworkURL == artworkURL,
                  environment.playbackController.snapshot.currentTrack?.artworkURL == artworkURL
            else { return }
            popupItem.image = image ?? Self.placeholderArtwork
        }
    }

    private func retrievePopupArtwork(from artworkURL: URL) async -> UIImage? {
        await withCheckedContinuation { continuation in
            KingfisherManager.shared.retrieveImage(with: artworkURL) { result in
                switch result {
                case let .success(value):
                    continuation.resume(returning: value.image)
                case let .failure(error):
                    AppLog.warning(self, "retrievePopupArtwork failed url=\(artworkURL.absoluteString) error=\(error.localizedDescription)")
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

// MARK: - LNPopupBarDataSource

extension MainController: LNPopupBarDataSource {
    func popupBar(_: LNPopupBar, popupItemBefore popupItem: LNPopupItem) -> LNPopupItem? {
        popupPagingHandler.popupItemBefore(popupItem)
    }

    func popupBar(_: LNPopupBar, popupItemAfter popupItem: LNPopupItem) -> LNPopupItem? {
        popupPagingHandler.popupItemAfter(popupItem)
    }
}

// MARK: - LNPopupBarDelegate

extension MainController: LNPopupBarDelegate {
    func popupBar(
        _: LNPopupBar,
        didDisplay newPopupItem: LNPopupItem,
        previous previousPopupItem: LNPopupItem?,
    ) {
        popupPagingHandler.didDisplay(newPopupItem, previous: previousPopupItem)
    }
}

// MARK: - LNPopupPresentationDelegate

extension MainController: LNPopupPresentationDelegate {
    func popupPresentationController(
        _: UIViewController,
        willOpenPopupWithContentController _: UIViewController,
        animated _: Bool,
    ) {
        isNowPlayingPopupOpen = true
        nowPlayingPopupContentViewController?.prepareForPopupOpen()
        setNeedsStatusBarAppearanceUpdate()
    }

    func popupPresentationController(
        _: UIViewController,
        willClosePopupWithContentController _: UIViewController,
        animated _: Bool,
    ) {
        setNeedsStatusBarAppearanceUpdate()
    }

    func popupPresentationController(
        _: UIViewController,
        didClosePopupWithContentController _: UIViewController,
        animated _: Bool,
    ) {
        setNeedsStatusBarAppearanceUpdate()

        isNowPlayingPopupOpen = false
    }
}

// MARK: - Popup Bar Context Menu

extension MainController: UIContextMenuInteractionDelegate {
    func contextMenuInteraction(
        _: UIContextMenuInteraction,
        configurationForMenuAtLocation _: CGPoint,
    ) -> UIContextMenuConfiguration? {
        guard let track = environment.playbackController.snapshot.currentTrack else {
            return nil
        }

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            self?.buildPopupContextMenu(for: track)
        }
    }

    private func buildPopupContextMenu(for track: PlaybackTrack) -> UIMenu? {
        let entry = track.playlistEntry
        let snapshot = environment.playbackController.snapshot

        return popupSongContextMenuProvider.menu(
            title: track.title.sanitizedTrackTitle,
            for: entry,
            context: .library,
            configuration: .init(
                availablePlaylists: { [weak self] in
                    self?.environment.playlistStore.playlists ?? []
                },
                showInAlbum: { [weak self] in
                    guard let self,
                          let nav = activeContentNavigationController
                    else { return }
                    let helper = AlbumNavigationHelper(
                        environment: environment,
                        viewController: nav.topViewController,
                    )
                    helper.pushAlbumDetail(songID: track.id, albumID: track.albumID, albumName: track.albumName ?? "", artistName: track.artistName)
                },
                primaryActions: popupPlaybackMenuProvider.songPrimaryActions(
                    trackProvider: { [weak self] in
                        self?.environment.playbackController.snapshot.currentTrack
                    },
                    queueProvider: { [weak self] in
                        self?.environment.playbackController.snapshot.queue ?? []
                    },
                    sourceProvider: { snapshot.source ?? .library },
                ),
            ),
        )
    }
}
