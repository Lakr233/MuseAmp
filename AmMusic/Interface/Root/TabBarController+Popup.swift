import AmMusicPlayerKit
import Combine
import Kingfisher
import LNPopupController
import UIKit

extension TabBarController {
    func prepareNowPlayingPopupContentViewController() {
        let contentViewController = makeNowPlayingPopupContentViewController()
        contentViewController.loadViewIfNeeded()
        updateNowPlayingPopupItem(using: environment.playbackController.snapshot)
    }

    func configurePopupBar() {
        popupBar.customBarViewController = nil
        popupBar.barStyle = .floating
        popupBar.progressViewStyle = .bottom
        popupBar.usesContentControllersAsDataSource = false
        popupBar.dataSource = self
        popupBar.delegate = self
    }

    func bindPlaybackPopup() {
        playbackPopupContentCancellable = environment.playbackController.$snapshot
            .removeDuplicates { lhs, rhs in
                lhs.currentTrack == rhs.currentTrack
                    && lhs.state == rhs.state
                    && lhs.upcoming == rhs.upcoming
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in
                self?.syncPopupPresentation(with: snapshot)
            }

        playbackPopupProgressCancellable = environment.playbackController.$snapshot
            .removeDuplicates { lhs, rhs in
                lhs.currentTime == rhs.currentTime
                    && lhs.duration == rhs.duration
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in
                self?.updatePopupProgress(using: snapshot)
            }
    }

    private func syncPopupPresentation(with snapshot: PlaybackSnapshot) {
        guard !isPagingCooldownActive else {
            updatePopupProgress(using: snapshot)
            return
        }

        updateNowPlayingPopupItem(using: snapshot)

        guard snapshot.currentTrack != nil else {
            if popupPresentationState == .barPresented {
                dismissPopupBar(animated: true)
            }
            return
        }

        ensureNowPlayingPopupPresented(openFullscreen: false, animated: true)
    }

    private var isPagingCooldownActive: Bool {
        guard let deadline = popupPagingCooldownDate else { return false }
        return Date() < deadline
    }

    private func ensureNowPlayingPopupPresented(openFullscreen: Bool, animated: Bool) {
        let contentViewController = nowPlayingPopupContentViewController ?? makeNowPlayingPopupContentViewController()
        updateNowPlayingPopupItem(using: environment.playbackController.snapshot)

        if popupPresentationState == .barHidden || popupContent !== contentViewController {
            presentPopupBar(with: contentViewController, openPopup: openFullscreen, animated: animated)
            return
        }

        guard openFullscreen, popupPresentationState != .open else {
            return
        }
        openPopup(animated: animated)
    }

    private func makeNowPlayingPopupContentViewController() -> NowPlayingViewController {
        if let nowPlayingPopupContentViewController {
            return nowPlayingPopupContentViewController
        }

        let controller = NowPlayingViewController(environment: environment)
        controller.title = String(localized: "Now Playing")
        nowPlayingPopupContentViewController = controller
        return controller
    }

    private func updateNowPlayingPopupItem(using snapshot: PlaybackSnapshot) {
        _ = makeNowPlayingPopupContentViewController()

        let popupItem: LNPopupItem
        if let existing = popupBar.popupItem {
            popupItem = existing
        } else {
            popupItem = LNPopupItem()
            popupBar.popupItem = popupItem
        }

        if let currentTrack = snapshot.currentTrack {
            if popupItem.title != currentTrack.title {
                popupItem.title = currentTrack.title
            }
            if popupItem.subtitle != currentTrack.artistName {
                popupItem.subtitle = currentTrack.artistName
            }
            updatePopupBarButtonItems(using: snapshot, popupItem: popupItem)
            popupItem.progress = Float(progress(for: snapshot))
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
            popupItem.barButtonItems = nil
            popupItem.progress = 0
            popupItem.accessibilityProgressValue = nil
            popupItem.userInfo = nil
            updatePopupArtwork(for: nil, popupItem: popupItem)
        }
    }

    private func updatePopupProgress(using snapshot: PlaybackSnapshot) {
        guard let popupItem = popupBar.popupItem,
              snapshot.currentTrack != nil
        else {
            return
        }

        popupItem.progress = Float(progress(for: snapshot))
        popupItem.accessibilityProgressValue = "\(formattedPlaybackTime(snapshot.currentTime)) / \(formattedPlaybackTime(snapshot.duration))"
    }

    private func progress(for snapshot: PlaybackSnapshot) -> Double {
        guard snapshot.duration > 0 else {
            return 0
        }

        return min(max(snapshot.currentTime / snapshot.duration, 0), 1)
    }

    private func updatePopupBarButtonItems(using snapshot: PlaybackSnapshot, popupItem: LNPopupItem) {
        let playPauseImage = UIImage(systemName: snapshot.state == .playing ? "pause.fill" : "play.fill")
        let canAdvance = !snapshot.upcoming.isEmpty || snapshot.repeatMode != .off

        if popupButtonsOwner === popupItem,
           let playPause = popupPlayPauseItem,
           let next = popupNextItem
        {
            playPause.image = playPauseImage
            next.isEnabled = canAdvance
            return
        }

        let playPause = UIBarButtonItem(
            image: playPauseImage,
            primaryAction: UIAction { [weak self] _ in
                self?.environment.playbackController.togglePlayPause()
            }
        )
        playPause.accessibilityIdentifier = "popup.playPause"

        let next = UIBarButtonItem(
            image: UIImage(systemName: "forward.fill"),
            primaryAction: UIAction { [weak self] _ in
                self?.environment.playbackController.next()
            }
        )
        next.accessibilityIdentifier = "popup.next"
        next.isEnabled = canAdvance

        popupPlayPauseItem = playPause
        popupNextItem = next
        popupButtonsOwner = popupItem
        popupItem.barButtonItems = [playPause, next]
    }

    private static let placeholderArtwork: UIImage =
        Bundle.appIcon ?? UIImage(systemName: "music.note")!

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
            else {
                return
            }
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

// MARK: - Popup Bar Paging (LNPopupBarDataSource & LNPopupBarDelegate)

extension TabBarController: LNPopupBarDataSource {
    func popupBar(_: LNPopupBar, popupItemBefore popupItem: LNPopupItem) -> LNPopupItem? {
        let snapshot = environment.playbackController.snapshot
        guard let queueIndex = popupItem.userInfo?["queueIndex"] as? Int else {
            return nil
        }

        let previousIndex = queueIndex - 1
        guard snapshot.queue.indices.contains(previousIndex) else {
            return nil
        }

        return makePopupItem(for: snapshot.queue[previousIndex], queueIndex: previousIndex)
    }

    func popupBar(_: LNPopupBar, popupItemAfter popupItem: LNPopupItem) -> LNPopupItem? {
        let snapshot = environment.playbackController.snapshot
        guard let queueIndex = popupItem.userInfo?["queueIndex"] as? Int else {
            return nil
        }

        let nextIndex = queueIndex + 1
        guard snapshot.queue.indices.contains(nextIndex) else {
            return nil
        }

        return makePopupItem(for: snapshot.queue[nextIndex], queueIndex: nextIndex)
    }

    private func makePopupItem(for track: PlaybackTrack, queueIndex: Int) -> LNPopupItem {
        let item = LNPopupItem()
        item.title = track.title
        item.subtitle = track.artistName
        item.image = Self.placeholderArtwork
        item.progress = 0
        item.userInfo = [
            "trackID": track.id,
            "queueIndex": queueIndex,
        ]

        if let artworkURL = track.artworkURL {
            if artworkURL.isFileURL {
                item.image = UIImage(contentsOfFile: artworkURL.path) ?? Self.placeholderArtwork
            } else {
                KingfisherManager.shared.retrieveImage(with: artworkURL) { result in
                    if case let .success(value) = result {
                        DispatchQueue.main.async {
                            item.image = value.image
                        }
                    }
                }
            }
        }

        return item
    }
}

extension TabBarController: LNPopupBarDelegate {
    func popupBar(_: LNPopupBar, didDisplay newPopupItem: LNPopupItem, previous previousPopupItem: LNPopupItem?) {
        guard let previousPopupItem,
              let newIndex = newPopupItem.userInfo?["queueIndex"] as? Int,
              let previousIndex = previousPopupItem.userInfo?["queueIndex"] as? Int,
              newIndex != previousIndex
        else {
            return
        }

        popupPagingCooldownDate = Date().addingTimeInterval(0.5)
        environment.playbackController.skipToQueueTrack(at: newIndex)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            popupPagingCooldownDate = nil
            let snapshot = environment.playbackController.snapshot
            updateNowPlayingPopupItem(using: snapshot)
        }
    }
}

// MARK: - Popup Presentation Delegate

extension TabBarController: LNPopupPresentationDelegate {
    func popupPresentationController(
        _: UIViewController,
        willOpenPopupWithContentController _: UIViewController,
        animated _: Bool
    ) {
        isNowPlayingPopupOpen = true
        nowPlayingPopupContentViewController?.prepareForPopupOpen()
        setNeedsStatusBarAppearanceUpdate()
    }

    func popupPresentationController(
        _: UIViewController,
        willClosePopupWithContentController _: UIViewController,
        animated _: Bool
    ) {
        isNowPlayingPopupOpen = false
        setNeedsStatusBarAppearanceUpdate()
    }

    func popupPresentationController(
        _: UIViewController,
        didClosePopupWithContentController _: UIViewController,
        animated _: Bool
    ) {
        isNowPlayingPopupOpen = false
        setNeedsStatusBarAppearanceUpdate()

        guard environment.playbackController.snapshot.currentTrack == nil else {
            return
        }
        dismissPopupBar(animated: true)
    }
}
