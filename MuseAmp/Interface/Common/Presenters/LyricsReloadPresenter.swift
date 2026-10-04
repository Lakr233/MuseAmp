//
//  LyricsReloadPresenter.swift
//  MuseAmp
//
//  Created by @Lakr233 on 2026/04/13.
//

import AlertController
import UIKit

@MainActor
final class LyricsReloadPresenter {
    private let reloadService: LyricsReloadService
    private weak var viewController: UIViewController?

    init(reloadService: LyricsReloadService, viewController: UIViewController) {
        self.reloadService = reloadService
        self.viewController = viewController
    }

    func reloadLyrics(for trackID: String, title: String?) {
        guard let viewController else { return }
        let message = title ?? String(localized: "Fetching lyrics…")
        ProgressActionPresenter.run(
            on: viewController,
            title: String(localized: "Reloading Lyrics"),
            message: message,
            action: { [reloadService] in
                _ = try await reloadService.reloadLyrics(for: trackID)
            },
            onSuccess: { _ in },
            onFailure: { [weak self] error in
                self?.presentFailure(error)
            },
        )
    }

    private func presentFailure(_ error: any Error) {
        guard let viewController else { return }
        let alert = AlertViewController(
            title: "Failed to Reload Lyrics",
            message: .init(error.localizedDescription),
        ) { context in
            context.addAction(title: "OK", attribute: .accent) {
                context.dispose()
            }
        }
        viewController.present(alert, animated: true)
    }
}
