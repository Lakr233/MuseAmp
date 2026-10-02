import Foundation
@testable import MuseAmp

/// Answers the `getLyrics` requests an `APIClient` sends, so lyrics code can be
/// tested without a server. Requests are routed by the track ID they ask for,
/// so suites running in parallel never receive each other's replies.
final nonisolated class LyricsServerStub: @unchecked Sendable {
    static let emptyLyricsReply = #"{"subsonic-response":{"status":"ok","version":"1.16.1","lyrics":{}}}"#
    static let notFoundReply = #"{"subsonic-response":{"status":"failed","version":"1.16.1","error":{"code":70,"message":"apple api request failed: 404 Not Found"}}}"#

    static func lyricsReply(_ text: String) throws -> String {
        let body: [String: Any] = [
            "subsonic-response": [
                "status": "ok",
                "version": "1.16.1",
                "lyrics": ["value": text],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: body)
        return String(decoding: data, as: UTF8.self)
    }

    private let lock = NSLock()
    private var reply: String
    private var statusCode: Int
    private var requests = 0

    init(trackIDs: [String], reply: String, statusCode: Int = 200) {
        self.reply = reply
        self.statusCode = statusCode
        LyricsServerStubURLProtocol.route(trackIDs: trackIDs, to: self)
    }

    var requestCount: Int {
        lock.withLock { requests }
    }

    func setReply(_ reply: String) {
        lock.withLock { self.reply = reply }
    }

    func setStatusCode(_ statusCode: Int) {
        lock.withLock { self.statusCode = statusCode }
    }

    @MainActor
    func makeAPIClient() -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LyricsServerStubURLProtocol.self]
        return APIClient(
            baseURL: URL(string: "https://lyrics.stub.test/rest")!,
            session: URLSession(configuration: configuration),
        )
    }

    fileprivate func respond() -> (statusCode: Int, body: Data) {
        lock.withLock {
            requests += 1
            return (statusCode, Data(reply.utf8))
        }
    }
}

private final nonisolated class LyricsServerStubURLProtocol: URLProtocol {
    private final nonisolated class Routes: @unchecked Sendable {
        let lock = NSLock()
        var stubs: [String: LyricsServerStub] = [:]
    }

    private static let routes = Routes()

    static func route(trackIDs: [String], to stub: LyricsServerStub) {
        routes.lock.withLock {
            for trackID in trackIDs {
                routes.stubs[trackID] = stub
            }
        }
    }

    private static func stub(for request: URLRequest) -> LyricsServerStub? {
        guard let url = request.url,
              url.lastPathComponent == "getLyrics.view",
              let trackID = URLComponents(url: url, resolvingAgainstBaseURL: false)?
              .queryItems?
              .first(where: { $0.name == "id" })?
              .value
        else {
            return nil
        }
        return routes.lock.withLock { routes.stubs[trackID] }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url, let stub = Self.stub(for: request) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        let reply = stub.respond()
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: reply.statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"],
        ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
