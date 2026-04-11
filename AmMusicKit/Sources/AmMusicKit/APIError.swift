//
//  APIError.swift
//  AmMusicKit
//
//  Created by @Lakr233 on 2026/04/11.
//

import Foundation

public enum APIError: LocalizedError, Sendable {
    case invalidRequest
    case invalidResponse
    case requestFailed(statusCode: Int)
    case decodingFailed(message: String)
    case transportFailed(message: String)

    public var errorDescription: String? {
        switch self {
        case .invalidRequest:
            String(localized: "The request could not be created.", bundle: .module)
        case .invalidResponse:
            String(localized: "The server returned an invalid response.", bundle: .module)
        case let .requestFailed(statusCode):
            String(
                format: String(localized: "The server returned HTTP %ld.", bundle: .module),
                locale: .current,
                statusCode,
            )
        case let .decodingFailed(message):
            message
        case let .transportFailed(message):
            message
        }
    }
}
