//
//  DownloadJobRow.swift
//  AmMusicDatabaseKit
//
//  Created by @Lakr233 on 2026/04/11.
//

import Foundation
@preconcurrency import WCDBSwift

struct DownloadJobRow: Codable, TableCodable {
    static let tableName = "download_jobs"

    var jobID: String
    var trackID: String
    var albumID: String
    var targetRelativePath: String
    var sourceURL: String?
    var title: String
    var artistName: String
    var albumTitle: String?
    var artworkURL: String?
    var status: String
    var progress: Double
    var retryCount: Int
    var errorMessage: String?
    var createdAt: Date
    var updatedAt: Date

    init(from model: DownloadJob) {
        jobID = model.jobID
        trackID = model.trackID
        albumID = model.albumID
        targetRelativePath = model.targetRelativePath
        sourceURL = model.sourceURL
        title = model.title
        artistName = model.artistName
        albumTitle = model.albumTitle
        artworkURL = model.artworkURL
        status = model.status.rawValue
        progress = model.progress
        retryCount = model.retryCount
        errorMessage = model.errorMessage
        createdAt = model.createdAt
        updatedAt = model.updatedAt
    }

    func toModel() -> DownloadJob {
        DownloadJob(
            jobID: jobID,
            trackID: trackID,
            albumID: albumID,
            targetRelativePath: targetRelativePath,
            sourceURL: sourceURL,
            title: title,
            artistName: artistName,
            albumTitle: albumTitle,
            artworkURL: artworkURL,
            status: DownloadJobStatus(rawValue: status) ?? .queued,
            progress: progress,
            retryCount: retryCount,
            errorMessage: errorMessage,
            createdAt: createdAt,
            updatedAt: updatedAt,
        )
    }

    enum CodingKeys: String, CodingTableKey {
        typealias Root = DownloadJobRow

        static let objectRelationalMapping = TableBinding(CodingKeys.self) {
            BindColumnConstraint(jobID, isPrimary: true, isNotNull: true, isUnique: true)
            BindColumnConstraint(trackID, isNotNull: true, defaultTo: "")
            BindColumnConstraint(albumID, isNotNull: true, defaultTo: "")
            BindColumnConstraint(targetRelativePath, isNotNull: true, defaultTo: "")
            BindColumnConstraint(title, isNotNull: true, defaultTo: "")
            BindColumnConstraint(artistName, isNotNull: true, defaultTo: "")
            BindColumnConstraint(status, isNotNull: true, defaultTo: DownloadJobStatus.queued.rawValue)
            BindColumnConstraint(progress, isNotNull: true, defaultTo: 0)
            BindColumnConstraint(retryCount, isNotNull: true, defaultTo: 0)
            BindColumnConstraint(createdAt, isNotNull: true, defaultTo: 0)
            BindColumnConstraint(updatedAt, isNotNull: true, defaultTo: 0)

            BindIndex(trackID, namedWith: "_download_track_index")
            BindIndex(status, namedWith: "_download_status_index")
            BindIndex(updatedAt, namedWith: "_download_updated_index")
        }

        case jobID = "job_id"
        case trackID = "track_id"
        case albumID = "album_id"
        case targetRelativePath = "target_relative_path"
        case sourceURL = "source_url"
        case title
        case artistName = "artist_name"
        case albumTitle = "album_title"
        case artworkURL = "artwork_url"
        case status
        case progress
        case retryCount = "retry_count"
        case errorMessage = "error_message"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
