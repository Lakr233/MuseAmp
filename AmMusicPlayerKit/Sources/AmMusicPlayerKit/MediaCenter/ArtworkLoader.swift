//
//  ArtworkLoader.swift
//  AmMusicPlayerKit
//
//  Created by @Lakr233 on 2026/04/11.
//

#if os(iOS) || os(tvOS)
    import Kingfisher
    import MediaPlayer
    import UIKit

    @MainActor
    final class ArtworkLoader {
        private var currentItemID: String?

        func loadArtwork(url: URL, for itemID: String) async -> MPMediaItemArtwork? {
            currentItemID = itemID

            let capturedID = itemID

            let image: UIImage? = await withCheckedContinuation { continuation in
                KingfisherManager.shared.retrieveImage(with: url) { result in
                    switch result {
                    case let .success(value):
                        continuation.resume(returning: value.image)
                    case .failure:
                        continuation.resume(returning: nil)
                    }
                }
            }

            guard currentItemID == capturedID, let image else { return nil }
            return Self.makeArtwork(from: image)
        }

        func cancelCurrent() {
            currentItemID = nil
        }

        private nonisolated static func makeArtwork(from image: UIImage) -> MPMediaItemArtwork {
            MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
    }

#else
    import Foundation

    @MainActor
    final class ArtworkLoader {
        func loadArtwork(url _: URL, for _: String) async -> Any? {
            nil
        }

        func cancelCurrent() {}
    }
#endif
