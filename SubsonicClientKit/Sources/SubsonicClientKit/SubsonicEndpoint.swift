//
//  SubsonicEndpoint.swift
//  SubsonicClientKit
//
//  Created by @Lakr233 on 2026/04/14.
//

import CryptoKit
import Foundation

enum SubsonicAuthenticationMode: String, Sendable {
    case token
    case plain
}

struct SubsonicAuthorization: Sendable {
    let username: String
    let password: String
    let mode: SubsonicAuthenticationMode
    let tokenSalt: String

    var queryItems: [URLQueryItem] {
        var items = [URLQueryItem(name: "u", value: username)]
        switch mode {
        case .token:
            items.append(URLQueryItem(name: "t", value: Self.md5Hex(password + tokenSalt)))
            items.append(URLQueryItem(name: "s", value: tokenSalt))
        case .plain:
            items.append(URLQueryItem(name: "p", value: password))
        }
        return items
    }

    private static func md5Hex(_ value: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

enum SubsonicEndpoint: Sendable {
    case ping
    case search(query: String, type: SearchType, limit: Int, offset: Int)
    case album(id: String)
    case song(id: String)
    case lyrics(id: String)
    case stream(id: String)
    case coverArt(id: String)

    private static let apiVersion = "1.16.1"
    private static let clientName = "museamp"

    var cacheIdentifier: String {
        switch self {
        case .ping:
            "ping"
        case let .search(query, type, limit, offset):
            "search:\(type.rawValue):\(query):\(limit):\(offset)"
        case let .album(id):
            "album:\(id)"
        case let .song(id):
            "song:\(id)"
        case let .lyrics(id):
            "lyrics:\(id)"
        case let .stream(id):
            "stream:\(id)"
        case let .coverArt(id):
            "cover-art:\(id)"
        }
    }

    func url(baseURL: URL, authorization: SubsonicAuthorization) throws -> URL {
        guard
            var components = URLComponents(
                url: baseURL.appendingPathComponent("\(actionName).view"),
                resolvingAgainstBaseURL: false,
            )
        else {
            throw APIError.invalidRequest
        }

        components.queryItems = fixedQueryItems
            + authorization.queryItems
            + requestQueryItems

        guard let url = components.url else {
            throw APIError.invalidRequest
        }
        return url
    }
}

private extension SubsonicEndpoint {
    var actionName: String {
        switch self {
        case .ping:
            "ping"
        case .search:
            "search3"
        case .album:
            "getAlbum"
        case .song:
            "getSong"
        case .lyrics:
            "getLyrics"
        case .stream:
            "stream"
        case .coverArt:
            "getCoverArt"
        }
    }

    var fixedQueryItems: [URLQueryItem] {
        var items = [
            URLQueryItem(name: "v", value: Self.apiVersion),
            URLQueryItem(name: "c", value: Self.clientName),
        ]

        switch self {
        case .stream, .coverArt:
            break
        default:
            items.append(URLQueryItem(name: "f", value: "json"))
        }

        return items
    }

    var requestQueryItems: [URLQueryItem] {
        switch self {
        case .ping:
            []
        case let .search(query, type, limit, offset):
            switch type {
            case .song:
                [
                    URLQueryItem(name: "query", value: query),
                    URLQueryItem(name: "songCount", value: "\(limit)"),
                    URLQueryItem(name: "songOffset", value: "\(offset)"),
                    URLQueryItem(name: "albumCount", value: "0"),
                    URLQueryItem(name: "artistCount", value: "0"),
                ]
            case .album:
                [
                    URLQueryItem(name: "query", value: query),
                    URLQueryItem(name: "albumCount", value: "\(limit)"),
                    URLQueryItem(name: "albumOffset", value: "\(offset)"),
                    URLQueryItem(name: "songCount", value: "0"),
                    URLQueryItem(name: "artistCount", value: "0"),
                ]
            case .artist:
                [
                    URLQueryItem(name: "query", value: query),
                    URLQueryItem(name: "artistCount", value: "\(limit)"),
                    URLQueryItem(name: "artistOffset", value: "\(offset)"),
                    URLQueryItem(name: "songCount", value: "0"),
                    URLQueryItem(name: "albumCount", value: "0"),
                ]
            }
        case let .album(id), let .song(id), let .lyrics(id), let .stream(id), let .coverArt(id):
            [URLQueryItem(name: "id", value: id)]
        }
    }
}
