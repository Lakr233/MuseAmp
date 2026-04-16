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
    case artist(id: String)
    case album(id: String)
    case song(id: String)
    case lyrics(id: String)
    case stream(id: String)
    case coverArt(id: String, size: String?)

    private static let apiVersion = "1.16.1"
    private static let clientName = "museamp"

    var cacheIdentifier: String {
        switch self {
        case .ping:
            "ping"
        case let .search(query, type, limit, offset):
            "search:\(type.rawValue):\(query):\(limit):\(offset)"
        case let .artist(id):
            "artist:\(id)"
        case let .album(id):
            "album:\(id)"
        case let .song(id):
            "song:\(id)"
        case let .lyrics(id):
            "lyrics:\(id)"
        case let .stream(id):
            "stream:\(id)"
        case let .coverArt(id, size):
            "cover-art:\(id):\(size ?? "")"
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
        case .artist:
            "getArtist"
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
            return []
        case let .search(query, type, limit, offset):
            switch type {
            case .song:
                return [
                    URLQueryItem(name: "query", value: query),
                    URLQueryItem(name: "songCount", value: "\(limit)"),
                    URLQueryItem(name: "songOffset", value: "\(offset)"),
                    URLQueryItem(name: "albumCount", value: "0"),
                    URLQueryItem(name: "artistCount", value: "0"),
                ]
            case .album:
                return [
                    URLQueryItem(name: "query", value: query),
                    URLQueryItem(name: "albumCount", value: "\(limit)"),
                    URLQueryItem(name: "albumOffset", value: "\(offset)"),
                    URLQueryItem(name: "songCount", value: "0"),
                    URLQueryItem(name: "artistCount", value: "0"),
                ]
            case .artist:
                return [
                    URLQueryItem(name: "query", value: query),
                    URLQueryItem(name: "artistCount", value: "\(limit)"),
                    URLQueryItem(name: "artistOffset", value: "\(offset)"),
                    URLQueryItem(name: "songCount", value: "0"),
                    URLQueryItem(name: "albumCount", value: "0"),
                ]
            }
        case let .artist(id), let .album(id), let .song(id), let .lyrics(id), let .stream(id):
            return [URLQueryItem(name: "id", value: id)]
        case let .coverArt(id, size):
            var items = [URLQueryItem(name: "id", value: id)]
            if let size {
                items.append(URLQueryItem(name: "size", value: size))
            }
            return items
        }
    }
}
