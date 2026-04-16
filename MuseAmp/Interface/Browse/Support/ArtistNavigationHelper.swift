//
//  ArtistNavigationHelper.swift
//  MuseAmp
//
//  Created by @libr on 2026/04/16.
//

import SubsonicClientKit
import UIKit

@MainActor
final class ArtistNavigationHelper {
    private let environment: AppEnvironment
    private weak var viewController: UIViewController?

    init(environment: AppEnvironment, viewController: UIViewController?) {
        self.environment = environment
        self.viewController = viewController
    }

    func pushArtistDetail(artist: CatalogArtist) {
        guard !artist.id.isEmpty else { return }
        let viewController = ArtistDetailViewController(artist: artist, environment: environment)
        self.viewController?.navigationController?.pushViewController(viewController, animated: true)
    }

    func pushArtistDetail(artistID: String, artistName: String = "", artworkURL: String? = nil) {
        guard !artistID.isEmpty else { return }
        let stub = CatalogArtist(
            id: artistID,
            type: "artists",
            href: nil,
            attributes: CatalogArtistAttributes(
                name: artistName,
                artwork: artworkURL.map { Artwork(width: nil, height: nil, url: $0) },
            ),
        )
        pushArtistDetail(artist: stub)
    }
}
