@testable import AmMusic
import Foundation
import Testing

@Suite(.serialized)
struct APIClientTransferTests {
    @Test
    func `authenticate transfer posts password and returns token`() async throws {
        let client = makeClient { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/auth")

            let body = try requestBody(from: request)
            let payload = try JSONDecoder().decode(SyncAuthRequest.self, from: body)
            #expect(payload.password == "482916")

            let response = try #require(
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"],
                ),
            )
            let data = try JSONEncoder().encode(
                SyncAuthResponse(success: true, token: "token-123", message: nil),
            )
            return (response, data)
        }

        let token = try await client.authenticateTransfer(
            endpoint: SyncEndpoint(host: "example.local", port: 18080),
            password: "482916",
        )

        #expect(token == "token-123")
    }

    @Test
    func `fetch manifest sends bearer token`() async throws {
        let client = makeClient { request in
            #expect(request.httpMethod == "GET")
            #expect(request.url?.path == "/manifest")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer auth-token")

            let manifest = SyncManifest(
                deviceName: "Phone",
                entries: [
                    SyncManifestEntry(
                        trackID: "1234567890",
                        albumID: "9988776655",
                        title: "Song",
                        artistName: "Artist",
                        albumTitle: "Album",
                        durationSeconds: 123,
                        fileSizeBytes: 1024,
                        fileExtension: "m4a",
                    ),
                ],
            )
            let response = try #require(
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"],
                ),
            )
            let data = try JSONEncoder().encode(manifest)
            return (response, data)
        }

        let manifest = try await client.fetchTransferManifest(
            endpoint: SyncEndpoint(host: "example.local", port: 18080),
            token: "auth-token",
        )

        #expect(manifest.deviceName == "Phone")
        #expect(manifest.entries.count == 1)
        #expect(manifest.entries.first?.trackID == "1234567890")
    }

    @Test
    func `download transfer track writes file contents`() async throws {
        let expectedData = Data("hello transfer".utf8)
        let client = makeClient { request in
            #expect(request.httpMethod == "GET")
            #expect(request.url?.path == "/track/1234567890")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer auth-token")

            let response = try #require(
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: [
                        "Content-Type": "application/octet-stream",
                        "Content-Length": "\(expectedData.count)",
                    ],
                ),
            )
            return (response, expectedData)
        }

        let destinationDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("APIClientTransferTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: destinationDirectory) }

        let destinationURL = destinationDirectory.appendingPathComponent("track.m4a")
        let entry = SyncManifestEntry(
            trackID: "1234567890",
            albumID: "9988776655",
            title: "Song",
            artistName: "Artist",
            albumTitle: "Album",
            durationSeconds: 120,
            fileSizeBytes: Int64(expectedData.count),
            fileExtension: "m4a",
        )

        let fileURL = try await client.downloadTransferTrack(
            endpoint: SyncEndpoint(host: "example.local", port: 18080),
            token: "auth-token",
            entry: entry,
            to: destinationURL,
        )

        #expect(fileURL == destinationURL)
        #expect(try Data(contentsOf: destinationURL) == expectedData)
    }

    @Test
    func `download transfer track removes destination file after http failure`() async throws {
        let client = makeClient { request in
            #expect(request.httpMethod == "GET")
            #expect(request.url?.path == "/track/1234567890")

            let response = try #require(
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 401,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "text/plain; charset=utf-8"],
                ),
            )
            return (response, Data("Unauthorized.".utf8))
        }

        let destinationDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("APIClientTransferTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: destinationDirectory) }

        let destinationURL = destinationDirectory.appendingPathComponent("track.m4a")
        let entry = SyncManifestEntry(
            trackID: "1234567890",
            albumID: "9988776655",
            title: "Song",
            artistName: "Artist",
            albumTitle: "Album",
            durationSeconds: 120,
            fileSizeBytes: 64,
            fileExtension: "m4a",
        )

        do {
            _ = try await client.downloadTransferTrack(
                endpoint: SyncEndpoint(host: "example.local", port: 18080),
                token: "auth-token",
                entry: entry,
                to: destinationURL,
            )
            Issue.record("Expected HTTP failure")
        } catch let error as SyncTransferError {
            switch error {
            case let .httpFailure(statusCode, message):
                #expect(statusCode == 401)
                #expect(message == "Unauthorized.")
            default:
                Issue.record("Unexpected sync transfer error: \(error.localizedDescription)")
            }
        }

        #expect(FileManager.default.fileExists(atPath: destinationURL.path) == false)
    }
}

private extension APIClientTransferTests {
    func makeClient(
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data),
    ) -> APIClient {
        MockTransferURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockTransferURLProtocol.self]
        let session = URLSession(configuration: configuration)
        return APIClient(
            baseURL: URL(string: "https://fallback.example.com")!,
            session: session,
        )
    }

    func requestBody(from request: URLRequest) throws -> Data {
        if let body = request.httpBody {
            return body
        }

        guard let stream = request.httpBodyStream else {
            throw URLError(.badURL)
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let readCount = stream.read(&buffer, maxLength: buffer.count)
            guard readCount >= 0 else {
                throw stream.streamError ?? URLError(.cannotDecodeRawData)
            }
            guard readCount > 0 else {
                break
            }
            data.append(buffer, count: readCount)
        }
        return data
    }
}

private final class MockTransferURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        request.url != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
