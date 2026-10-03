//
//  SyncProtocol.swift
//  MuseAmp
//
//  Created by @Lakr233 on 2026/04/11.
//

import Foundation

nonisolated enum SyncConstants {
    static let bonjourType = "_museamp-sync._tcp."
    static let protocolVersion = "4"

    static func isCompatible(protocolVersion: String?) -> Bool {
        protocolVersion == Self.protocolVersion
    }
}

nonisolated enum SyncPeerRole: String, Codable, Hashable {
    case sender
    case receiver
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
        let effectivePath = path.hasPrefix("/") ? path : "/\(path)"
        if host.contains(":") {
            return URL(string: "http://[\(host)]:\(port)\(effectivePath)")
        }
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = port
        components.path = effectivePath
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
        if let percentIndex = normalized.firstIndex(of: "%") {
            normalized = String(normalized[..<percentIndex])
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
    let protocolVersion: String?

    init(
        serviceName: String,
        password: String,
        deviceName: String,
        fallbackEndpoints: [SyncEndpoint],
        protocolVersion: String? = SyncConstants.protocolVersion,
    ) {
        self.serviceName = serviceName
        self.password = password
        self.deviceName = deviceName
        self.fallbackEndpoints = fallbackEndpoints
        self.protocolVersion = protocolVersion
    }
}

nonisolated struct SyncReceiverHandshakeInfo: Codable, Hashable {
    let serviceName: String
    let deviceName: String
    let protocolVersion: String
    let pairingCode: String?

    init(
        serviceName: String,
        deviceName: String,
        protocolVersion: String = SyncConstants.protocolVersion,
        pairingCode: String? = nil,
    ) {
        self.serviceName = serviceName
        self.deviceName = deviceName
        self.protocolVersion = protocolVersion
        self.pairingCode = pairingCode
    }

    var bonjourServiceDisplayName: String {
        serviceName + ".local"
    }
}

nonisolated struct SyncPlaylistSession: Codable, Hashable {
    let playlistName: String
    let sessionID: String
    let orderedTrackIDs: [String]
    let expectedTrackCount: Int
    let expectedUniqueTrackCount: Int
    let createdAt: Date
    let updatedAt: Date

    init(
        playlistName: String,
        sessionID: String = UUID().uuidString,
        orderedTrackIDs: [String],
        expectedTrackCount: Int? = nil,
        expectedUniqueTrackCount: Int? = nil,
        createdAt: Date = .init(),
        updatedAt: Date = .init(),
    ) {
        let orderedUniqueTrackIDs = orderedTrackIDs.orderedUnique()
        self.playlistName = playlistName
        self.sessionID = sessionID
        self.orderedTrackIDs = orderedTrackIDs
        self.expectedTrackCount = expectedTrackCount ?? orderedTrackIDs.count
        self.expectedUniqueTrackCount = expectedUniqueTrackCount ?? orderedUniqueTrackIDs.count
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var uniqueTrackIDs: [String] {
        orderedTrackIDs.orderedUnique()
    }
}

nonisolated struct SyncManifestEntry: Codable, Hashable {
    let trackID: String
    let albumID: String?
    let title: String
    let artistName: String
    let albumTitle: String
    let durationSeconds: Double
    let fileExtension: String
}

nonisolated struct SyncManifest: Codable {
    let deviceName: String
    let protocolVersion: String?
    let session: SyncPlaylistSession?
    let entries: [SyncManifestEntry]

    init(
        deviceName: String,
        protocolVersion: String? = SyncConstants.protocolVersion,
        session: SyncPlaylistSession? = nil,
        entries: [SyncManifestEntry],
    ) {
        self.deviceName = deviceName
        self.protocolVersion = protocolVersion
        self.session = session
        self.entries = entries
    }
}

nonisolated enum SyncSenderTransferPhase: String, Codable, Hashable {
    case waitingForReceiver
    case receiverConnected
    case manifestServed
    case sendingTrack
    case completed
}

nonisolated struct SyncSenderTransferProgress: Hashable {
    let phase: SyncSenderTransferPhase
    let receiverDeviceName: String?
    let playlistName: String?
    let currentTrackCount: Int
    let totalTrackCount: Int
    let currentTrackTitle: String?

    /// The receiver finished without getting every offered song, for
    /// example because some downloads failed.
    var isMissingTracks: Bool {
        phase == .completed && currentTrackCount < totalTrackCount
    }

    static func waiting(
        playlistName: String?,
        totalTrackCount: Int,
    ) -> SyncSenderTransferProgress {
        SyncSenderTransferProgress(
            phase: .waitingForReceiver,
            receiverDeviceName: nil,
            playlistName: playlistName,
            currentTrackCount: 0,
            totalTrackCount: totalTrackCount,
            currentTrackTitle: nil,
        )
    }
}

nonisolated struct SyncAuthRequest: Codable {
    let password: String
    let deviceName: String
}

nonisolated struct SyncAuthResponse: Codable {
    let success: Bool
    let token: String?
    let message: String?
}

/// Sent by the receiver once it has finished a transfer, so the sender can
/// stop waiting for songs the receiver never requests because it already
/// has them.
nonisolated struct SyncTransferCompletion: Codable {
    let alreadyInLibraryTrackCount: Int
}

nonisolated struct DiscoveredDevice: Hashable {
    let serviceName: String
    let deviceName: String
    let protocolVersion: String?
    let role: SyncPeerRole
    let preferredEndpoint: SyncEndpoint?
    let fallbackEndpoints: [SyncEndpoint]
    let port: Int

    var isCompatibleProtocolVersion: Bool {
        SyncConstants.isCompatible(protocolVersion: protocolVersion)
    }

    var primaryDisplayAddress: String {
        preferredEndpoint?.displayString
            ?? fallbackEndpoints.first?.displayString
            ?? String(localized: "No Endpoint")
    }

    var bonjourServiceDisplayName: String {
        serviceName + ".local"
    }
}

nonisolated enum SyncTransferError: LocalizedError {
    case invalidServerResponse
    case httpFailure(Int, String?)
    case missingAuthToken
    case noPreparedSongs
    case noResolvableEndpoint
    case invalidPlaylistSession
    case unsupportedProtocolVersion(String?)

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
        case .invalidPlaylistSession:
            return String(localized: "The playlist session metadata was invalid.")
        case let .unsupportedProtocolVersion(version):
            if let version, !version.isEmpty {
                return String(localized: "The other device is using incompatible transfer protocol version \(version). Update both devices and try again.")
            }
            return String(localized: "The other device is using an incompatible transfer protocol version. Update both devices and try again.")
        }
    }
}

private nonisolated extension Array where Element: Hashable {
    func orderedUnique() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
