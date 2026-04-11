//
//  DownloadJob.swift
//  AmMusicDatabaseKit
//
//  Created by @Lakr233 on 2026/04/11.
//

import Foundation

public struct DownloadJob: Sendable, Codable, Hashable, Identifiable {
    public var id: String {
        jobID
    }

    public let jobID: String
    public let trackID: String
    public let albumID: String
    public let targetRelativePath: String
    public let sourceURL: String?
    public let title: String
    public let artistName: String
    public let albumTitle: String?
    public let artworkURL: String?
    public let status: DownloadJobStatus
    public let progress: Double
    public let retryCount: Int
    public let errorMessage: String?
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        jobID: String = UUID().uuidString,
        trackID: String,
        albumID: String,
        targetRelativePath: String,
        sourceURL: String? = nil,
        title: String,
        artistName: String,
        albumTitle: String? = nil,
        artworkURL: String? = nil,
        status: DownloadJobStatus = .queued,
        progress: Double = 0,
        retryCount: Int = 0,
        errorMessage: String? = nil,
        createdAt: Date = .init(),
        updatedAt: Date = .init(),
    ) {
        self.jobID = jobID
        self.trackID = trackID
        self.albumID = albumID
        self.targetRelativePath = targetRelativePath
        self.sourceURL = sourceURL
        self.title = title
        self.artistName = artistName
        self.albumTitle = albumTitle
        self.artworkURL = artworkURL
        self.status = status
        self.progress = progress
        self.retryCount = retryCount
        self.errorMessage = errorMessage
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
