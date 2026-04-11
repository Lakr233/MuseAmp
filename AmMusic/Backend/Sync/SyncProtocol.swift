//
//  SyncProtocol.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import Foundation

nonisolated enum SyncConstants {
    static let bonjourType = "_ammusic-sync._tcp."
    static let protocolVersion = "1"
}

nonisolated struct SyncEndpoint: Hashable, Codable {
    let host: String
    let port: Int

    init(host: String, port: Int) {
        self.host = Self.normalizeHost(host)
        self.port = port
    }

    var displayHost: String {
        if host.contains(":") {
            return "[\(host)]"
        }
        return host
    }

    var displayString: String {
        "\(displayHost):\(port)"
    }

    func url(path: String) -> URL? {
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = port
        components.path = path.hasPrefix("/") ? path : "/\(path)"
        return components.url
    }

    static func parse(_ rawValue: String) throws -> SyncEndpoint {
        let input = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else {
            throw SyncEndpointParseError.emptyInput
        }

        if input.hasPrefix("[") {
            guard let closingBracketIndex = input.firstIndex(of: "]") else {
                throw SyncEndpointParseError.invalidFormat(input)
            }
            let host = String(input[input.index(after: input.startIndex) ..< closingBracketIndex])
            let portStart = input.index(after: closingBracketIndex)
            guard portStart < input.endIndex, input[portStart] == ":" else {
                throw SyncEndpointParseError.missingPort(input)
            }
            let portString = String(input[input.index(after: portStart) ..< input.endIndex])
            return try makeEndpoint(host: host, portString: portString, rawValue: input)
        }

        guard input.count(where: { $0 == ":" }) == 1,
              let separatorIndex = input.lastIndex(of: ":")
        else {
            throw SyncEndpointParseError.invalidFormat(input)
        }

        let host = String(input[..<separatorIndex])
        let portString = String(input[input.index(after: separatorIndex) ..< input.endIndex])
        return try makeEndpoint(host: host, portString: portString, rawValue: input)
    }
}

nonisolated extension SyncEndpoint {
    static func normalizeHost(_ rawHost: String) -> String {
        var normalized = rawHost.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasPrefix("["),
           normalized.hasSuffix("]"),
           normalized.count >= 2
        {
            normalized = String(normalized.dropFirst().dropLast())
        }
        if normalized.hasSuffix(".") {
            normalized.removeLast()
        }
        return normalized
    }

    private static func makeEndpoint(
        host: String,
        portString: String,
        rawValue: String,
    ) throws -> SyncEndpoint {
        let normalizedHost = normalizeHost(host)
        guard !normalizedHost.isEmpty else {
            throw SyncEndpointParseError.emptyHost(rawValue)
        }
        guard let port = Int(portString), (1 ... 65535).contains(port) else {
            throw SyncEndpointParseError.invalidPort(rawValue)
        }
        return SyncEndpoint(host: normalizedHost, port: port)
    }
}

nonisolated enum SyncEndpointParseError: LocalizedError {
    case emptyInput
    case emptyHost(String)
    case missingPort(String)
    case invalidPort(String)
    case invalidFormat(String)

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            String(localized: "Enter an address in the form host:port.")
        case let .emptyHost(value):
            String(localized: "Missing host name in \"\(value)\".")
        case let .missingPort(value):
            String(localized: "Missing port in \"\(value)\".")
        case let .invalidPort(value):
            String(localized: "Invalid port in \"\(value)\".")
        case let .invalidFormat(value):
            String(localized: "Invalid address format \"\(value)\". Use hostname:port, IPv4:port, or [IPv6]:port.")
        }
    }
}

nonisolated struct SyncConnectionInfo: Codable {
    let serviceName: String
    let password: String
    let deviceName: String
    let fallbackEndpoints: [SyncEndpoint]
}

nonisolated struct SyncManifestEntry: Codable, Hashable {
    let trackID: String
    let albumID: String?
    let title: String
    let artistName: String
    let albumTitle: String
    let durationSeconds: Double
    let fileSizeBytes: Int64
    let fileExtension: String
}

nonisolated struct SyncManifest: Codable {
    let deviceName: String
    let entries: [SyncManifestEntry]
}

nonisolated struct SyncAuthRequest: Codable {
    let password: String
}

nonisolated struct SyncAuthResponse: Codable {
    let success: Bool
    let token: String?
    let message: String?
}

nonisolated struct DiscoveredDevice: Hashable {
    let serviceName: String
    let deviceName: String
    let preferredEndpoint: SyncEndpoint?
    let fallbackEndpoints: [SyncEndpoint]
    let port: Int

    var primaryDisplayAddress: String {
        preferredEndpoint?.displayString
            ?? fallbackEndpoints.first?.displayString
            ?? String(localized: "No Endpoint")
    }
}

nonisolated enum SyncTransferError: LocalizedError {
    case invalidServerResponse
    case httpFailure(Int, String?)
    case missingAuthToken
    case noPreparedSongs
    case noResolvableEndpoint
    case receiverInterrupted
    case senderInterrupted

    var errorDescription: String? {
        switch self {
        case .invalidServerResponse:
            return String(localized: "The other device returned an invalid response.")
        case let .httpFailure(statusCode, message):
            if let message, !message.isEmpty {
                return message
            }
            return String(localized: "The transfer request failed with status code \(statusCode).")
        case .missingAuthToken:
            return String(localized: "The other device did not return a transfer token.")
        case .noPreparedSongs:
            return String(localized: "None of the selected songs could be prepared for transfer.")
        case .noResolvableEndpoint:
            return String(localized: "No reachable address was available for the selected device.")
        case .receiverInterrupted:
            return String(localized: "Receiving was interrupted because the app left the foreground.")
        case .senderInterrupted:
            return String(localized: "Sending was interrupted because the app left the foreground.")
        }
    }
}
