//
//  SyncServer+RequestParsing.swift
//  MuseAmp
//
//  Created by @Lakr233 on 2026/04/11.
//

import Foundation

nonisolated extension SyncServer {
    nonisolated struct HTTPRequest {
        let method: String
        let path: String
        let headers: [String: String]
        let body: Data
    }

    nonisolated enum ReceiveOutcome {
        case request(HTTPRequest)
        case needMoreData(Data)
        case error(body: String)
    }

    nonisolated static let maxRequestBufferSize = 1024 * 1024
    nonisolated static let oversizedRequestMessage = String(localized: "Request too large.")
    nonisolated static let invalidRequestMessage = String(localized: "Invalid request.")

    nonisolated static func receiveOutcome(
        buffer: Data,
        chunk: Data?,
        isComplete: Bool,
    ) -> ReceiveOutcome {
        var accumulated = buffer
        if let chunk, !chunk.isEmpty {
            accumulated.append(chunk)
        }

        if accumulated.count > maxRequestBufferSize {
            AppLog.warning("SyncServer", "receiveRequest buffer exceeded limit=\(maxRequestBufferSize)")
            return .error(body: oversizedRequestMessage)
        }

        switch parseRequest(from: accumulated) {
        case let .request(request):
            return .request(request)
        case .invalidContentLength:
            return .error(body: invalidRequestMessage)
        case .oversizedBody:
            AppLog.warning("SyncServer", "receiveRequest buffer exceeded limit=\(maxRequestBufferSize)")
            return .error(body: oversizedRequestMessage)
        case .incomplete:
            break
        }

        if isComplete {
            return .error(body: invalidRequestMessage)
        }

        return .needMoreData(accumulated)
    }
}

private nonisolated extension SyncServer {
    nonisolated enum ParsedRequest {
        case request(HTTPRequest)
        case incomplete
        case invalidContentLength
        case oversizedBody
    }

    nonisolated static func parseRequest(from data: Data) -> ParsedRequest {
        let delimiter = Data("\r\n\r\n".utf8)
        guard let range = data.range(of: delimiter) else {
            return .incomplete
        }

        let head = data[..<range.lowerBound]
        guard let headString = String(data: head, encoding: .utf8) else {
            return .incomplete
        }

        let headerLines = headString.components(separatedBy: "\r\n")
        guard let requestLine = headerLines.first else {
            return .incomplete
        }
        let requestParts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
        guard requestParts.count >= 2 else {
            return .incomplete
        }

        var headers: [String: String] = [:]
        for line in headerLines.dropFirst() {
            guard let separatorIndex = line.firstIndex(of: ":") else {
                continue
            }
            let key = line[..<separatorIndex].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: separatorIndex)...].trimmingCharacters(in: .whitespacesAndNewlines)
            headers[key] = value
        }

        // The header comes from an unauthenticated peer, so it is range
        // checked before it is used in any index arithmetic.
        var contentLength = 0
        if let rawContentLength = headers["content-length"] {
            guard let value = Int(rawContentLength), value >= 0 else {
                return .invalidContentLength
            }
            guard value <= maxRequestBufferSize else {
                return .oversizedBody
            }
            contentLength = value
        }

        let bodyStart = range.upperBound
        guard data.endIndex - bodyStart >= contentLength else {
            return .incomplete
        }

        let body = Data(data[bodyStart ..< bodyStart + contentLength])
        return .request(HTTPRequest(
            method: String(requestParts[0]),
            path: String(requestParts[1]),
            headers: headers,
            body: body,
        ))
    }
}
