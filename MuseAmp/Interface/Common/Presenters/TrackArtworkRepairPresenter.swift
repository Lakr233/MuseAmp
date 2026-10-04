//
//  TrackArtworkRepairPresenter.swift
//  MuseAmp
//
//  Created by @Lakr233 on 2026/04/12.
//

import AlertController
import MuseAmpDatabaseKit
import UIKit

enum TrackArtworkRepairPresenter {
    static func makeMenuAction(handler: @escaping UIActionHandler) -> UIAction {
        UIAction(
            title: String(localized: "Repair Album Artwork"),
            image: UIImage(systemName: "photo.badge.arrow.down"),
            handler: handler,
        )
    }

    static func present(
        on viewController: UIViewController,
        track: AudioTrackRecord,
        repairService: TrackArtworkRepairService,
    ) {
        ProgressActionPresenter.run(
            on: viewController,
            title: String(localized: "Repairing Artwork"),
            message: String(localized: "Redownloading album artwork and updating the audio file..."),
            action: {
                try await repairService.repairArtwork(for: track)
            },
            onSuccess: { [weak viewController] _ in
                guard let viewController else { return }
                presentSuccessAlert(
                    on: viewController,
                    trackTitle: track.title,
                )
            },
            onFailure: { [weak viewController] error in
                guard let viewController else { return }
                presentFailureAlert(
                    on: viewController,
                    trackTitle: track.title,
                    error: error,
                )
            },
        )
    }

    @MainActor
    static func presentSuccessAlert(
        on viewController: UIViewController,
        trackTitle: String,
    ) {
        let alert = AlertViewController(
            title: "Artwork Repair Complete",
            message: "Refreshed album artwork for \"\(trackTitle)\" and updated the local audio file.",
        ) { context in
            context.addAction(title: "OK", attribute: .accent) {
                context.dispose()
            }
        }
        viewController.present(alert, animated: true)
    }

    @MainActor
    static func presentFailureAlert(
        on viewController: UIViewController,
        trackTitle: String,
        error: Error,
    ) {
        let alert = AlertViewController(
            title: "Artwork Repair Failed",
            message: "Couldn't repair artwork for \"\(trackTitle)\".\n\n\(error.localizedDescription)",
        ) { context in
            context.addAction(title: "OK", attribute: .accent) {
                context.dispose()
            }
        }
        viewController.present(alert, animated: true)
    }
}
