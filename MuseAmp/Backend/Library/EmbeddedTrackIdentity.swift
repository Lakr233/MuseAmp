@preconcurrency import AVFoundation
import CryptoKit
import Foundation
import MuseAmpDatabaseKit

/// File-backed identity shared by import, export and LAN transfer. Catalog IDs
/// keep their original meaning; local IDs never identify a server resource.
nonisolated struct EmbeddedTrackIdentity: Equatable, Sendable {
    static let source = "MuseAmp"

    let trackID: String
    let albumID: String
    var artworkURL: URL?

    enum IdentityError: Error {
        case invalidComment
    }

    static func isTrackID(_ value: String) -> Bool {
        value.isCatalogID || isLocalTrackID(value)
    }

    static func isAlbumID(_ value: String) -> Bool {
        value.isCatalogID || isLocalAlbumID(value)
    }

    static func isLocalTrackID(_ value: String) -> Bool {
        isLocalID(value, prefix: "local-track-")
    }

    static func isLocalAlbumID(_ value: String) -> Bool {
        isLocalID(value, prefix: "local-album-")
    }

    private static func isLocalID(_ value: String, prefix: String) -> Bool {
        guard value.hasPrefix(prefix) else { return false }
        let digest = value.dropFirst(prefix.count)
        return digest.count == 64 && digest.utf8.allSatisfy {
            (48 ... 57).contains($0) || (97 ... 102).contains($0)
        }
    }

    /// Ordinary comments are not identity metadata. A damaged identity must
    /// not silently acquire a different ID through the import fallback.
    static func payload(from comment: String) throws -> [String: Any]? {
        let text = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("{") else { return nil }
        let hasSourceMarker = text.range(of: #""source"\s*:\s*"MuseAmp""#, options: .regularExpression) != nil
        var isIdentity = hasSourceMarker
        do {
            let data = Data(text.utf8)
            guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            let hasValidPair = (payload["trackID"] as? String).map(isTrackID) == true
                && (payload["albumID"] as? String).map(isAlbumID) == true
            isIdentity = payload["source"] as? String == source || hasValidPair
            guard isIdentity else { return nil }
            nonisolated struct Fields: Decodable {
                let v: Int?
                let trackID: String
                let albumID: String
            }
            let fields = try JSONDecoder().decode(Fields.self, from: data)
            guard fields.v == nil || fields.v == 1,
                  isTrackID(fields.trackID), isAlbumID(fields.albumID)
            else {
                throw IdentityError.invalidComment
            }
            return payload
        } catch {
            AppLog.warning("EmbeddedTrackIdentity", "Unable to decode comment identity: \(error)")
            if isIdentity {
                throw IdentityError.invalidComment
            }
            return nil
        }
    }

    static func read(from items: [AVMetadataItem]) async throws -> EmbeddedTrackIdentity? {
        var hasInvalidIdentity = false
        for item in items where AVMetadataHelper.isComment(item) {
            do {
                guard let comment = try await item.load(.stringValue),
                      let payload = try payload(from: comment),
                      let trackID = payload["trackID"] as? String,
                      let albumID = payload["albumID"] as? String
                else { continue }
                let artworkURL = (payload["artworkURL"] as? String)
                    .flatMap { URL(string: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
                return EmbeddedTrackIdentity(trackID: trackID, albumID: albumID, artworkURL: artworkURL)
            } catch IdentityError.invalidComment {
                hasInvalidIdentity = true
            } catch {
                AppLog.warning("EmbeddedTrackIdentity", "Unable to read identity comment: \(error)")
                throw error
            }
        }
        if hasInvalidIdentity {
            throw IdentityError.invalidComment
        }
        return nil
    }

    static func local(fileURL: URL, album: String?, albumArtist: String?, artist: String) throws -> EmbeddedTrackIdentity {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer {
            do {
                try handle.close()
            } catch {
                AppLog.warning("EmbeddedTrackIdentity", "Unable to close source file: \(error)")
            }
        }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            try Task.checkCancellation()
            hasher.update(data: chunk)
        }
        let trackID = "local-track-" + hex(hasher.finalize())
        let albumKey: [String] = if let album, !album.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ["album", normalized(album), normalized(albumArtist?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? artist)]
        } else {
            ["unassigned", trackID]
        }
        let data = try JSONEncoder().encode(albumKey)
        let albumID = "local-album-" + hex(SHA256.hash(data: data))
        return EmbeddedTrackIdentity(trackID: trackID, albumID: albumID)
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
            .precomposedStringWithCanonicalMapping
    }

    private static func hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}
