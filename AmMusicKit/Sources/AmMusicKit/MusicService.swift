//
//  MusicService.swift
//  AmMusicKit
//
//  Created by @Lakr233 on 2026/04/11.
//

import Foundation

public protocol MusicService: AnyObject {
    func search(
        query: String,
        type: SearchType,
        limit: Int,
        offset: Int,
        cacheSearchResponses: Bool,
        prefetchSongMetadata: Bool,
    ) async throws -> SearchResponse

    func album(id: String, storefront: String?) async throws -> AlbumResponse
    func song(id: String, storefront: String?) async throws -> SongResponse
    func playback(id: String, storefront: String?, redirect: Bool?) async throws -> PlaybackInfo
    func lyrics(id: String, storefront: String?) async throws -> LyricsResponse
}

public extension MusicService {
    func album(id: String) async throws -> AlbumResponse {
        try await album(id: id, storefront: nil)
    }

    func song(id: String) async throws -> SongResponse {
        try await song(id: id, storefront: nil)
    }

    func playback(id: String) async throws -> PlaybackInfo {
        try await playback(id: id, storefront: nil, redirect: nil)
    }

    func lyrics(id: String) async throws -> LyricsResponse {
        try await lyrics(id: id, storefront: nil)
    }
}
