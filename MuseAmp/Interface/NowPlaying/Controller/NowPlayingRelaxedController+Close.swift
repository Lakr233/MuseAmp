//
//  NowPlayingRelaxedController+Close.swift
//  MuseAmp
//
//  Created by @Lakr233 on 2026/10/03.
//

import LNPopupController
import SnapKit
import UIKit

// MARK: - Close Button

/// A pointer cannot drag the popup closed on Mac, so the relaxed layout
/// keeps its own close button in the top trailing corner, on iPad as well.
extension NowPlayingRelaxedController {
    enum CloseButtonStyle {
        /// Swap for "chevron.down" to drop the circle.
        static let symbolName = "chevron.down.circle.fill"
        /// Draws the circle at the size of the LNPopupController glass
        /// button it replaces.
        static let symbolPointSize: CGFloat = 26
        static let symbolWeight: UIImage.SymbolWeight = .medium
        static let alpha: CGFloat = 0.5
        static let hitSide: CGFloat = 44
        /// Centres the symbol where LNPopupController placed its button,
        /// 26 pt from the top and trailing edges.
        static let edgeInset: CGFloat = 4
        /// A critically damped spring that leaves fast, like a flick, and
        /// settles off screen, so no overshoot can show.
        static let slideDuration: TimeInterval = 0.45
        static let slideDampingRatio: CGFloat = 1.0
        static let slideInitialVelocity: CGFloat = 0.8
    }

    func makeCloseButton() -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: CloseButtonStyle.symbolName)
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
            pointSize: CloseButtonStyle.symbolPointSize,
            weight: CloseButtonStyle.symbolWeight,
        )
        configuration.baseForegroundColor = .white
        configuration.contentInsets = .zero

        let button = UIButton(configuration: configuration)
        button.preferredBehavioralStyle = .pad
        // A bare symbol: no hover platter behind it.
        button.isPointerInteractionEnabled = false
        button.alpha = CloseButtonStyle.alpha
        button.accessibilityIdentifier = "nowplaying.close"
        let title = String(localized: "Close Now Playing")
        button.accessibilityLabel = title
        button.toolTip = title
        button.addAction(
            UIAction { [weak self] _ in
                self?.closeBySlidingDown()
            },
            for: .touchUpInside,
        )
        return button
    }

    func installCloseButton() {
        view.addSubview(closeButton)
        closeButton.snp.makeConstraints { make in
            #if targetEnvironment(macCatalyst)
                // The title bar row, opposite the traffic lights.
                make.top.trailing.equalToSuperview().inset(CloseButtonStyle.edgeInset)
            #else
                make.top.trailing.equalTo(view.safeAreaLayoutGuide).inset(CloseButtonStyle.edgeInset)
            #endif
            make.size.equalTo(CloseButtonStyle.hitSide)
        }
    }

    /// LNPopupController closes by shrinking the content into the popup
    /// bar. Now Playing instead slides straight down.
    ///
    /// The slide moves a snapshot, not the popup content view itself:
    /// LNPopupController sets that view's frame on every container layout,
    /// and a frame set under a transform moves the view by the transform
    /// again. The popup closes at once without its own animation, so the bar
    /// is already in place under the snapshot and nothing else can change
    /// the slide while it runs.
    func closeBySlidingDown() {
        guard let container = popupPresentationContainer,
              container.popupPresentationState == .open
        else { return }
        let contentView = container.popupContentView

        guard let window = contentView.window,
              let snapshot = contentView.snapshotView(afterScreenUpdates: false)
        else {
            AppLog.warning(self, "closeBySlidingDown has no snapshot; closing without the slide")
            container.closePopup(animated: false)
            return
        }

        AppLog.info(self, "closeBySlidingDown height=\(contentView.bounds.height)")
        snapshot.frame = contentView.convert(contentView.bounds, to: window)
        window.addSubview(snapshot)
        container.closePopup(animated: false)

        Interface.springAnimate(
            duration: CloseButtonStyle.slideDuration,
            dampingRatio: CloseButtonStyle.slideDampingRatio,
            initialVelocity: CloseButtonStyle.slideInitialVelocity,
        ) {
            snapshot.transform = CGAffineTransform(translationX: 0, y: snapshot.bounds.height)
        } completion: { _ in
            // Runs when interrupted as well, so the snapshot never stays.
            snapshot.removeFromSuperview()
        }
    }
}
