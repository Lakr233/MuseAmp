//
//  SyncServer.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import Foundation
import Network

final nonisolated class SyncServer: @unchecked Sendable {
    nonisolated struct RunningServer {
        let port: Int
        let serviceName: String
        let preferredEndpoints: [SyncEndpoint]
    }

    nonisolated struct HTTPRequest {
        let method: String
        let path: String
        let headers: [String: String]
        let body: Data
    }

    nonisolated enum ReceiveOutcome {
        case request(HTTPRequest)
        case needMoreData(Data)
        case error(statusCode: Int, body: String)
    }

    nonisolated static let maxRequestBufferSize = 1024 * 1024
    nonisolated static let oversizedRequestMessage = String(localized: "Request too large.")
    nonisolated static let invalidRequestMessage = String(localized: "Invalid request.")

    nonisolated static func receiveOutcome(
        buffer: Data,
        chunk: Data?,
        isComplete: Bool,
    ) -> ReceiveOutcome {
        _receiveOutcome(buffer: buffer, chunk: chunk, isComplete: isComplete)
    }

    private let serviceName: String
    private let password: String
    private let manifest: SyncManifest
    private let preparedFiles: [String: URL]
    private let queue = DispatchQueue(label: "wiki.qaq.AmMusic.sync.server")
    private let tokenStore = TokenStore()

    private var listener: NWListener?
    private var connectionIDs: [ObjectIdentifier: NWConnection] = [:]

    init(
        serviceName: String,
        password: String,
        manifest: SyncManifest,
        preparedFiles: [String: URL],
    ) {
        self.serviceName = serviceName
        self.password = password
        self.manifest = manifest
        self.preparedFiles = preparedFiles
    }

    func start() async throws -> RunningServer {
        if let listener, let port = listener.port?.rawValue {
            return RunningServer(
                port: Int(port),
                serviceName: serviceName,
                preferredEndpoints: Self.preferredEndpoints(port: Int(port)),
            )
        }

        let listener = try NWListener(using: .tcp, on: .any)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }

        let once = ResumeOnce<RunningServer>()
        return try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    guard let self,
                          let port = listener.port?.rawValue
                    else {
                        once.resume(
                            continuation,
                            throwing: SyncTransferError.invalidServerResponse,
                        )
                        return
                    }
                    let runningServer = RunningServer(
                        port: Int(port),
                        serviceName: serviceName,
                        preferredEndpoints: Self.preferredEndpoints(port: Int(port)),
                    )
                    AppLog.info(
                        self,
                        "Sync server ready service=\(serviceName) port=\(port)",
                    )
                    once.resume(continuation, returning: runningServer)

                case let .failed(error):
                    AppLog.error(self ?? "SyncServer", "listener failed: \(error)")
                    once.resume(continuation, throwing: error)

                default:
                    break
                }
            }

            listener.start(queue: queue)
        }
    }

    func stop() async {
        AppLog.info(self, "Sync server stopping")
        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel()
        listener = nil

        for connection in connectionIDs.values {
            connection.cancel()
        }
        connectionIDs.removeAll()
        tokenStore.clear()
    }
}

private nonisolated extension SyncServer {
    final nonisolated class TokenStore: @unchecked Sendable {
        private let lock = NSLock()
        private var tokens: Set<String> = []

        func issueToken(for submittedPassword: String, expectedPassword: String) -> String? {
            guard submittedPassword == expectedPassword else {
                return nil
            }

            let token = UUID().uuidString
            lock.lock()
            tokens.insert(token)
            lock.unlock()
            return token
        }

        func contains(_ token: String) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return tokens.contains(token)
        }

        func clear() {
            lock.lock()
            tokens.removeAll()
            lock.unlock()
        }
    }

    final nonisolated class ResumeOnce<Value> {
        private let lock = NSLock()
        private var didResume = false

        func resume(
            _ continuation: CheckedContinuation<Value, any Error>,
            returning value: Value,
        ) {
            lock.lock()
            defer { lock.unlock() }
            guard !didResume else {
                return
            }
            didResume = true
            continuation.resume(returning: value)
        }

        func resume(
            _ continuation: CheckedContinuation<Value, any Error>,
            throwing error: any Error,
        ) {
            lock.lock()
            defer { lock.unlock() }
            guard !didResume else {
                return
            }
            didResume = true
            continuation.resume(throwing: error)
        }
    }

    nonisolated enum HTTPStatus: Int {
        case ok = 200
        case badRequest = 400
        case unauthorized = 401
        case notFound = 404
        case internalServerError = 500

        var reasonPhrase: String {
            switch self {
            case .ok:
                "OK"
            case .badRequest:
                "Bad Request"
            case .unauthorized:
                "Unauthorized"
            case .notFound:
                "Not Found"
            case .internalServerError:
                "Internal Server Error"
            }
        }
    }

    nonisolated func accept(_ connection: NWConnection) {
        let identifier = ObjectIdentifier(connection)
        connectionIDs[identifier] = connection
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            switch state {
            case .failed, .cancelled:
                guard let self, let connection else {
                    return
                }
                connectionIDs.removeValue(forKey: ObjectIdentifier(connection))
            default:
                break
            }
        }
        connection.start(queue: queue)
        receiveRequest(on: connection, buffer: Data())
    }

    nonisolated func receiveRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }

            if let error {
                AppLog.error(self, "receiveRequest failed: \(error)")
                connection.cancel()
                return
            }

            switch Self._receiveOutcome(buffer: buffer, chunk: data, isComplete: isComplete) {
            case let .request(request):
                process(request, on: connection)

            case let .needMoreData(accumulated):
                receiveRequest(on: connection, buffer: accumulated)

            case let .error(statusCode, body):
                if statusCode == HTTPStatus.badRequest.rawValue,
                   body == Self.oversizedRequestMessage
                {
                    AppLog.warning(self, "receiveRequest buffer exceeded limit=\(Self.maxRequestBufferSize)")
                }
                sendPlainResponse(
                    status: HTTPStatus(rawValue: statusCode) ?? .internalServerError,
                    body: body,
                    on: connection,
                )
            }
        }
    }

    nonisolated static func _receiveOutcome(
        buffer: Data,
        chunk: Data?,
        isComplete: Bool,
    ) -> ReceiveOutcome {
        var accumulated = buffer
        if let chunk, !chunk.isEmpty {
            accumulated.append(chunk)
        }

        if accumulated.count > maxRequestBufferSize {
            return .error(
                statusCode: HTTPStatus.badRequest.rawValue,
                body: oversizedRequestMessage,
            )
        }

        if let request = parseRequest(from: accumulated) {
            return .request(request)
        }

        if isComplete {
            return .error(
                statusCode: HTTPStatus.badRequest.rawValue,
                body: invalidRequestMessage,
            )
        }

        return .needMoreData(accumulated)
    }

    nonisolated static func parseRequest(from data: Data) -> HTTPRequest? {
        let delimiter = Data("\r\n\r\n".utf8)
        guard let range = data.range(of: delimiter) else {
            return nil
        }

        let head = data[..<range.lowerBound]
        guard let headString = String(data: head, encoding: .utf8) else {
            return nil
        }

        let headerLines = headString.components(separatedBy: "\r\n")
        guard let requestLine = headerLines.first else {
            return nil
        }
        let requestParts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
        guard requestParts.count >= 2 else {
            return nil
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

        let bodyStart = range.upperBound
        let contentLength = Int(headers["content-length"] ?? "") ?? 0
        guard data.count >= bodyStart + contentLength else {
            return nil
        }

        let body = Data(data[bodyStart ..< bodyStart + contentLength])
        return HTTPRequest(
            method: String(requestParts[0]),
            path: String(requestParts[1]),
            headers: headers,
            body: body,
        )
    }

    nonisolated func process(_ request: HTTPRequest, on connection: NWConnection) {
        AppLog.verbose(self, "process request method=\(request.method) path=\(request.path)")

        switch (request.method, request.path) {
        case ("POST", "/auth"):
            handleAuth(request, on: connection)

        case ("GET", "/manifest"):
            guard authorize(request) else {
                sendPlainResponse(
                    status: .unauthorized,
                    body: String(localized: "Unauthorized."),
                    on: connection,
                )
                return
            }
            sendJSONResponse(status: .ok, payload: manifest, on: connection)

        default:
            if request.method == "GET",
               request.path.hasPrefix("/track/")
            {
                guard authorize(request) else {
                    sendPlainResponse(
                        status: .unauthorized,
                        body: String(localized: "Unauthorized."),
                        on: connection,
                    )
                    return
                }
                handleTrack(request, on: connection)
            } else {
                sendPlainResponse(
                    status: .notFound,
                    body: String(localized: "Not Found."),
                    on: connection,
                )
            }
        }
    }

    nonisolated func handleAuth(_ request: HTTPRequest, on connection: NWConnection) {
        do {
            let authRequest = try JSONDecoder().decode(SyncAuthRequest.self, from: request.body)
            if let token = tokenStore.issueToken(
                for: authRequest.password,
                expectedPassword: password,
            ) {
                AppLog.info(self, "handleAuth succeeded")
                sendJSONResponse(
                    status: .ok,
                    payload: SyncAuthResponse(success: true, token: token, message: nil),
                    on: connection,
                )
                return
            }

            AppLog.warning(self, "handleAuth rejected incorrect password")
            sendJSONResponse(
                status: .unauthorized,
                payload: SyncAuthResponse(
                    success: false,
                    token: nil,
                    message: String(localized: "Incorrect password"),
                ),
                on: connection,
            )
        } catch {
            AppLog.error(self, "handleAuth decode failed: \(error.localizedDescription)")
            sendPlainResponse(
                status: .badRequest,
                body: String(localized: "Invalid auth payload."),
                on: connection,
            )
        }
    }

    nonisolated func handleTrack(_ request: HTTPRequest, on connection: NWConnection) {
        let trackID = String(request.path.dropFirst("/track/".count))
        guard let fileURL = preparedFiles[trackID] else {
            sendPlainResponse(
                status: .notFound,
                body: String(localized: "Track not found."),
                on: connection,
            )
            return
        }

        do {
            let fileSize = try (FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber)?.int64Value ?? 0
            let headerString = responseHeader(
                status: .ok,
                headers: [
                    "Content-Type": "application/octet-stream",
                    "Content-Length": "\(fileSize)",
                    "Connection": "close",
                ],
            )
            connection.send(content: Data(headerString.utf8), completion: .contentProcessed { [weak self] error in
                if let error {
                    AppLog.error(self ?? "SyncServer", "send header failed: \(error)")
                    connection.cancel()
                    return
                }
                self?.streamFile(at: fileURL, over: connection)
            })
        } catch {
            AppLog.error(self, "handleTrack failed trackID=\(trackID) error=\(error.localizedDescription)")
            sendPlainResponse(
                status: .internalServerError,
                body: error.localizedDescription,
                on: connection,
            )
        }
    }

    nonisolated func authorize(_ request: HTTPRequest) -> Bool {
        guard let authorization = request.headers["authorization"] else {
            return false
        }
        guard authorization.hasPrefix("Bearer ") else {
            return false
        }
        let token = String(authorization.dropFirst("Bearer ".count))
        return tokenStore.contains(token)
    }

    nonisolated func streamFile(at fileURL: URL, over connection: NWConnection) {
        do {
            let handle = try FileHandle(forReadingFrom: fileURL)
            streamChunk(from: handle, over: connection)
        } catch {
            AppLog.error(self, "streamFile open failed path=\(fileURL.path) error=\(error.localizedDescription)")
            connection.cancel()
        }
    }

    nonisolated func streamChunk(
        from handle: FileHandle,
        over connection: NWConnection,
    ) {
        let data = handle.readData(ofLength: 64 * 1024)
        guard !data.isEmpty else {
            try? handle.close()
            connection.cancel()
            return
        }

        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            if let error {
                AppLog.error(self ?? "SyncServer", "streamChunk failed: \(error)")
                try? handle.close()
                connection.cancel()
                return
            }
            self?.streamChunk(from: handle, over: connection)
        })
    }

    nonisolated func sendPlainResponse(
        status: HTTPStatus,
        body: String,
        on connection: NWConnection,
    ) {
        let bodyData = Data(body.utf8)
        let header = responseHeader(
            status: status,
            headers: [
                "Content-Type": "text/plain; charset=utf-8",
                "Content-Length": "\(bodyData.count)",
                "Connection": "close",
            ],
        )
        sendResponse(header: Data(header.utf8), body: bodyData, on: connection)
    }

    nonisolated func sendJSONResponse(
        status: HTTPStatus,
        payload: some Encodable,
        on connection: NWConnection,
    ) {
        do {
            let bodyData = try JSONEncoder().encode(payload)
            let header = responseHeader(
                status: status,
                headers: [
                    "Content-Type": "application/json",
                    "Content-Length": "\(bodyData.count)",
                    "Connection": "close",
                ],
            )
            sendResponse(header: Data(header.utf8), body: bodyData, on: connection)
        } catch {
            AppLog.error(self, "sendJSONResponse encode failed: \(error.localizedDescription)")
            sendPlainResponse(
                status: .internalServerError,
                body: error.localizedDescription,
                on: connection,
            )
        }
    }

    nonisolated func sendResponse(
        header: Data,
        body: Data,
        on connection: NWConnection,
    ) {
        connection.send(content: header, completion: .contentProcessed { error in
            if let error {
                AppLog.error(self, "sendResponse header failed: \(error)")
                connection.cancel()
                return
            }

            connection.send(content: body, completion: .contentProcessed { error in
                if let error {
                    AppLog.error(self, "sendResponse body failed: \(error)")
                }
                connection.cancel()
            })
        })
    }

    nonisolated func responseHeader(
        status: HTTPStatus,
        headers: [String: String],
    ) -> String {
        var lines = ["HTTP/1.1 \(status.rawValue) \(status.reasonPhrase)"]
        lines.append(contentsOf: headers.map { "\($0.key): \($0.value)" })
        lines.append("")
        lines.append("")
        return lines.joined(separator: "\r\n")
    }

    nonisolated static func preferredEndpoints(port: Int) -> [SyncEndpoint] {
        var endpoints: [SyncEndpoint] = []
        var seen = Set<SyncEndpoint>()

        let hostName = ProcessInfo.processInfo.hostName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !hostName.isEmpty {
            let endpoint = SyncEndpoint(host: hostName, port: port)
            endpoints.append(endpoint)
            seen.insert(endpoint)
        }

        var interfacePointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfacePointer) == 0, let firstAddress = interfacePointer else {
            return endpoints
        }
        defer { freeifaddrs(interfacePointer) }

        for pointer in sequence(first: firstAddress, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            let flags = Int32(interface.ifa_flags)
            guard (flags & IFF_UP) != 0,
                  (flags & IFF_LOOPBACK) == 0,
                  let address = interface.ifa_addr
            else {
                continue
            }

            let family = address.pointee.sa_family
            guard family == UInt8(AF_INET) || family == UInt8(AF_INET6) else {
                continue
            }

            var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let addressLength = family == UInt8(AF_INET)
                ? socklen_t(MemoryLayout<sockaddr_in>.size)
                : socklen_t(MemoryLayout<sockaddr_in6>.size)
            let result = getnameinfo(
                address,
                addressLength,
                &hostBuffer,
                socklen_t(hostBuffer.count),
                nil,
                0,
                NI_NUMERICHOST,
            )
            guard result == 0 else {
                continue
            }

            let host = String(cString: hostBuffer)
            let endpoint = SyncEndpoint(host: host, port: port)
            guard !seen.contains(endpoint) else {
                continue
            }
            endpoints.append(endpoint)
            seen.insert(endpoint)
        }

        return endpoints
    }
}
