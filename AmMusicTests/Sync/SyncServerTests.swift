@testable import AmMusic
import Foundation
import Testing

@Suite(.serialized)
struct SyncServerTests {
    @Test
    func `oversized request buffer is rejected with bad request`() {
        let chunk = Data(repeating: 0x41, count: SyncServer.maxRequestBufferSize + 1)

        switch SyncServer.receiveOutcome(buffer: Data(), chunk: chunk, isComplete: false) {
        case let .error(statusCode, body):
            #expect(statusCode == 400)
            #expect(body == SyncServer.oversizedRequestMessage)

        default:
            Issue.record("Expected oversized request to be rejected")
        }
    }

    @Test
    func `complete auth request is parsed before buffer limit`() throws {
        let body = try JSONEncoder().encode(SyncAuthRequest(password: "482916"))
        let requestHead = "POST /auth HTTP/1.1\r\n"
            + "Host: 127.0.0.1\r\n"
            + "Content-Type: application/json\r\n"
            + "Content-Length: \(body.count)\r\n"
            + "\r\n"
        var request = Data(requestHead.utf8)
        request.append(body)

        switch SyncServer.receiveOutcome(buffer: Data(), chunk: request, isComplete: false) {
        case let .request(parsedRequest):
            #expect(parsedRequest.method == "POST")
            #expect(parsedRequest.path == "/auth")
            #expect(parsedRequest.headers["content-type"] == "application/json")
            #expect(parsedRequest.body == body)

        default:
            Issue.record("Expected a complete auth request to be parsed")
        }
    }
}
