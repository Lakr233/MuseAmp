//
//  APIEndpoint.swift
//  AmMusicKit
//
//  Created by @Lakr233 on 2026/04/11.
//

import Foundation

enum APIEndpoint {
    case search(query: String, type: SearchType, limit: Int, offset: Int)
    case album(id: String, storefront: String?)
    case song(id: String, storefront: String?)
    case playback(id: String, storefront: String?, redirect: Bool?)
    case lyrics(id: String, storefront: String?)

    func urlRequest(baseURL: URL, authorizationToken: String? = nil) throws -> URLRequest {
        let endpointURL = baseURL.appendingPathComponent(path)
        guard var components = URLComponents(
            url: endpointURL,
            resolvingAgainstBaseURL: false,
        ) else {
            throw APIError.invalidRequest
        }

        let items = queryItems
        if items.isEmpty == false {
            components.queryItems = items
        }

        guard let url = components.url else {
            throw APIError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let headerValue = authorizationHeaderValue(from: authorizationToken) {
            request.setValue(headerValue, forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private var path: String {
        switch self {
        case .search:
            "search"
        case let .album(id, _):
            "album/\(id)"
        case let .song(id, _):
            "song/\(id)"
        case let .playback(id, _, _):
            "playback/\(id)"
        case let .lyrics(id, _):
            "lyrics/\(id)"
        }
    }

    private var queryItems: [URLQueryItem] {
        var items: [URLQueryItem] = []

        switch self {
        case let .search(query, type, limit, offset):
            items.append(URLQueryItem(name: "query", value: query))
            items.append(URLQueryItem(name: "type", value: type.rawValue))
            items.append(URLQueryItem(name: "limit", value: String(limit)))
            items.append(URLQueryItem(name: "offset", value: String(offset)))

        case let .album(_, storefront):
            if let storefront {
                items.append(URLQueryItem(name: "storefront", value: storefront))
            }

        case let .song(_, storefront):
            if let storefront {
                items.append(URLQueryItem(name: "storefront", value: storefront))
            }

        case let .playback(_, storefront, redirect):
            if let storefront {
                items.append(URLQueryItem(name: "storefront", value: storefront))
            }
            if let redirect {
                items.append(URLQueryItem(name: "redirect", value: redirect ? "true" : "false"))
            }

        case let .lyrics(_, storefront):
            if let storefront {
                items.append(URLQueryItem(name: "storefront", value: storefront))
            }
        }

        return items
    }

    private func authorizationHeaderValue(from token: String?) -> String? {
        guard let token else {
            return nil
        }
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return nil
        }
        if trimmed.lowercased().hasPrefix("bearer ") {
            return trimmed
        }
        return "Bearer \(trimmed)"
    }
}
