import AmMusicDatabaseKit
import Kingfisher
import UIKit

actor PlaylistCoverArtworkCache {
    private let directory: URL
    private let memoryCache = NSCache<NSString, UIImage>()

    init(directory: URL? = nil) {
        let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.directory = directory
            ?? cachesDirectory.appendingPathComponent("PlaylistCoverArtworkCache", isDirectory: true)
        memoryCache.countLimit = 512
    }

    func image(
        for playlist: Playlist,
        sideLength: CGFloat,
        scale: CGFloat,
        urlResolver: @escaping (String?, Int, Int) -> URL?
    ) async -> UIImage {
        let sidePixels = max(Int((sideLength * scale).rounded()), 1)
        let cacheKey = cacheKey(for: playlist, sidePixels: sidePixels)
        if let image = memoryCache.object(forKey: cacheKey as NSString) {
            AppLog.verbose(self, "playlist cover cache memory hit key=\(cacheKey)")
            return image
        }

        let fileURL = directory.appendingPathComponent(cacheKey).appendingPathExtension("png")
        if let image = UIImage(contentsOfFile: fileURL.path) {
            memoryCache.setObject(image, forKey: cacheKey as NSString)
            AppLog.verbose(self, "playlist cover cache disk hit key=\(cacheKey)")
            return image
        }

        let coverSongs = Self.uniqueCoverSongs(from: playlist.songs)
        let gridDimension = Self.gridDimension(for: coverSongs.count)
        let tileCount = gridDimension * gridDimension
        AppLog.info(
            self,
            "playlist cover cache render key=\(cacheKey) songs=\(playlist.songs.count) uniqueCovers=\(coverSongs.count) grid=\(gridDimension)x\(gridDimension)"
        )
        let images = await loadImages(
            from: Array(coverSongs.prefix(tileCount)),
            width: sidePixels / gridDimension,
            height: sidePixels / gridDimension,
            urlResolver: urlResolver
        )
        let successCount = images.reduce(into: 0) { count, image in
            if image != nil {
                count += 1
            }
        }
        if successCount == 0 {
            AppLog.warning(
                self,
                "playlist cover cache render produced no source images key=\(cacheKey) requestedTiles=\(tileCount)"
            )
        } else {
            AppLog.verbose(self, "playlist cover cache render loaded images key=\(cacheKey) success=\(successCount)/\(images.count)")
        }
        let image = Self.render(images: images, gridDimension: gridDimension, sideLength: sideLength, scale: scale)
        memoryCache.setObject(image, forKey: cacheKey as NSString)
        write(image: image, to: fileURL)
        return image
    }
}

private extension PlaylistCoverArtworkCache {
    static func gridDimension(for songCount: Int) -> Int {
        guard songCount > 0 else {
            return 1
        }
        return min(max(Int(floor(sqrt(Double(songCount)))), 1), 8)
    }

    static func uniqueCoverSongs(from songs: [PlaylistEntry]) -> [PlaylistEntry] {
        var seenKeys = Set<String>()
        var coverSongs: [PlaylistEntry] = []

        for song in songs {
            let key = coverIdentity(for: song)
            guard seenKeys.insert(key).inserted else {
                continue
            }
            coverSongs.append(song)
        }

        return coverSongs
    }

    static func coverIdentity(for entry: PlaylistEntry) -> String {
        if let artworkURL = normalizedIdentity(entry.artworkURL) {
            return "artwork:\(artworkURL)"
        }

        if let albumID = normalizedIdentity(entry.albumID), albumID != "unknown" {
            return "album-id:\(albumID)"
        }

        if let albumTitle = normalizedIdentity(entry.albumTitle), albumTitle != "unknown album" {
            return "album-name:\(albumTitle)"
        }

        return "song:\(entry.trackID)"
    }

    static func normalizedIdentity(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    static func render(images: [UIImage?], gridDimension: Int, sideLength: CGFloat, scale: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true

        let size = CGSize(width: sideLength, height: sideLength)
        let cellLength = sideLength / CGFloat(gridDimension)
        let placeholderColor = UIColor.systemGray5

        return UIGraphicsImageRenderer(size: size, format: format).image { rendererContext in
            placeholderColor.setFill()
            rendererContext.cgContext.fill(CGRect(origin: .zero, size: size))

            for index in 0 ..< (gridDimension * gridDimension) {
                let row = index / gridDimension
                let column = index % gridDimension
                let rect = CGRect(
                    x: CGFloat(column) * cellLength,
                    y: CGFloat(row) * cellLength,
                    width: cellLength,
                    height: cellLength
                )

                guard images.indices.contains(index) else {
                    placeholderColor.setFill()
                    rendererContext.cgContext.fill(rect)
                    continue
                }

                guard let image = images[index] else {
                    placeholderColor.setFill()
                    rendererContext.cgContext.fill(rect)
                    continue
                }
                drawAspectFill(image, in: rect)
            }
        }
    }

    static func drawAspectFill(_ image: UIImage, in rect: CGRect) {
        guard image.size.width > 0, image.size.height > 0 else {
            UIColor.systemGray5.setFill()
            UIRectFill(rect)
            return
        }

        let scale = max(rect.width / image.size.width, rect.height / image.size.height)
        let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let drawRect = CGRect(
            x: rect.midX - drawSize.width / 2,
            y: rect.midY - drawSize.height / 2,
            width: drawSize.width,
            height: drawSize.height
        )

        guard let context = UIGraphicsGetCurrentContext() else {
            image.draw(in: rect)
            return
        }

        context.saveGState()
        context.clip(to: rect)
        image.draw(in: drawRect)
        context.restoreGState()
    }

    func loadImages(
        from entries: [PlaylistEntry],
        width: Int,
        height: Int,
        urlResolver: @escaping (String?, Int, Int) -> URL?
    ) async -> [UIImage?] {
        var images: [UIImage?] = []
        for entry in entries {
            guard let url = urlResolver(entry.artworkURL, width, height) else {
                AppLog.verbose(self, "loadImages missing url trackID=\(entry.trackID) rawArtworkURL=\(entry.artworkURL ?? "nil")")
                images.append(nil)
                continue
            }
            await images.append(Self.retrieveImage(from: url))
        }
        return images
    }

    static func retrieveImage(from url: URL) async -> UIImage? {
        await withCheckedContinuation { continuation in
            KingfisherManager.shared.retrieveImage(with: url) { result in
                switch result {
                case let .success(value):
                    continuation.resume(returning: value.image)
                case .failure:
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    func cacheKey(for playlist: Playlist, sidePixels: Int) -> String {
        let timestamp = Int((playlist.updatedAt.timeIntervalSince1970 * 1000).rounded())
        return "v3-\(playlist.id.uuidString)-\(timestamp)-\(playlist.songs.count)-\(sidePixels)"
    }

    func write(image: UIImage, to fileURL: URL) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try image.pngData()?.write(to: fileURL, options: .atomic)
        } catch {
            AppLog.error(self, "write playlist cover cache failed url=\(fileURL.path) error=\(error.localizedDescription)")
        }
    }
}
