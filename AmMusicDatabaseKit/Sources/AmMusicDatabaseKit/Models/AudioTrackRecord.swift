//
//  AudioTrackRecord.swift
//  AmMusicDatabaseKit
//
//  Created by @Lakr233 on 2026/04/11.
//

import Foundation

public struct AudioTrackRecord: Sendable, Codable, Hashable, Identifiable {
    public var id: String {
        trackID
    }

    public let trackID: String
    public let albumID: String
    public let fileExtension: String
    public let relativePath: String
    public let fileSizeBytes: Int64
    public let fileModifiedAt: Date
    public let durationSeconds: Double
    public let title: String
    public let artistName: String
    public let albumTitle: String
    public let albumArtistName: String?
    public let trackNumber: Int?
    public let discNumber: Int?
    public let genreName: String?
    public let composerName: String?
    public let releaseDate: String?
    public let hasEmbeddedLyrics: Bool
    public let hasEmbeddedArtwork: Bool
    public let sourceKind: TrackSourceKind
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        trackID: String,
        albumID: String,
        fileExtension: String,
        relativePath: String,
        fileSizeBytes: Int64,
        fileModifiedAt: Date,
        durationSeconds: Double,
        title: String,
        artistName: String,
        albumTitle: String,
        albumArtistName: String? = nil,
        trackNumber: Int? = nil,
        discNumber: Int? = nil,
        genreName: String? = nil,
        composerName: String? = nil,
        releaseDate: String? = nil,
        hasEmbeddedLyrics: Bool = false,
        hasEmbeddedArtwork: Bool = false,
        sourceKind: TrackSourceKind = .unknown,
        createdAt: Date = .init(),
        updatedAt: Date = .init(),
    ) {
        self.trackID = trackID
        self.albumID = albumID
        self.fileExtension = fileExtension
        self.relativePath = relativePath
        self.fileSizeBytes = fileSizeBytes
        self.fileModifiedAt = fileModifiedAt
        self.durationSeconds = durationSeconds
        self.title = title
        self.artistName = artistName
        self.albumTitle = albumTitle
        self.albumArtistName = albumArtistName
        self.trackNumber = trackNumber
        self.discNumber = discNumber
        self.genreName = genreName
        self.composerName = composerName
        self.releaseDate = releaseDate
        self.hasEmbeddedLyrics = hasEmbeddedLyrics
        self.hasEmbeddedArtwork = hasEmbeddedArtwork
        self.sourceKind = sourceKind
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
