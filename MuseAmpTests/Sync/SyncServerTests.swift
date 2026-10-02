import Foundation
@testable import MuseAmp
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
        let body = try JSONEncoder().encode(
            SyncAuthRequest(password: "482916", deviceName: "Bedroom Apple TV"),
        )
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
            let payload = try JSONDecoder().decode(SyncAuthRequest.self, from: parsedRequest.body)
            #expect(payload.password == "482916")
            #expect(payload.deviceName == "Bedroom Apple TV")

        default:
            Issue.record("Expected a complete auth request to be parsed")
        }
    }

    @Test(arguments: ["-1", "abc", "1.5"])
    func `malformed content length is rejected instead of trapping`(contentLength: String) {
        let request = "GET /manifest HTTP/1.1\r\n"
            + "Host: 127.0.0.1\r\n"
            + "Content-Length: \(contentLength)\r\n"
            + "\r\n"

        switch SyncServer.receiveOutcome(buffer: Data(), chunk: Data(request.utf8), isComplete: false) {
        case let .error(statusCode, body):
            #expect(statusCode == 400)
            #expect(body == SyncServer.invalidRequestMessage)

        default:
            Issue.record("Expected Content-Length \(contentLength) to be rejected")
        }
    }

    @Test(arguments: ["\(Int.max)", "\(SyncServer.maxRequestBufferSize + 1)"])
    func `content length beyond the buffer limit is rejected`(contentLength: String) {
        let request = "POST /auth HTTP/1.1\r\n"
            + "Host: 127.0.0.1\r\n"
            + "Content-Length: \(contentLength)\r\n"
            + "\r\n"

        switch SyncServer.receiveOutcome(buffer: Data(), chunk: Data(request.utf8), isComplete: false) {
        case let .error(statusCode, body):
            #expect(statusCode == 400)
            #expect(body == SyncServer.oversizedRequestMessage)

        default:
            Issue.record("Expected Content-Length \(contentLength) to be rejected")
        }
    }

    @Test
    func `request waits for the rest of a declared body`() {
        let request = "POST /auth HTTP/1.1\r\n"
            + "Content-Length: 10\r\n"
            + "\r\n"
            + "12345"

        switch SyncServer.receiveOutcome(buffer: Data(), chunk: Data(request.utf8), isComplete: false) {
        case .needMoreData:
            break

        default:
            Issue.record("Expected the server to wait for the remaining body bytes")
        }
    }

    @Test
    func `receiver completion moves the sender to completed`() async throws {
        let manifest = SyncManifest(
            deviceName: "Sender",
            entries: ["1111111111", "2222222222", "3333333333"].map { trackID in
                SyncManifestEntry(
                    trackID: trackID,
                    albumID: "9988776655",
                    title: "Song \(trackID)",
                    artistName: "Artist",
                    albumTitle: "Album",
                    durationSeconds: 60,
                    fileExtension: "m4a",
                )
            },
        )
        let recorder = SenderProgressRecorder()
        let server = SyncServer(
            serviceName: "Sync Server Tests",
            password: "482916",
            manifest: manifest,
            preparedFiles: [:],
            onProgress: { recorder.append($0) },
        )
        let runningServer = try await server.start()
        let endpoint = SyncEndpoint(host: "127.0.0.1", port: runningServer.port)
        let fallbackURL = try #require(URL(string: "https://fallback.example.com"))
        let client = APIClient(
            baseURL: fallbackURL,
            session: URLSession(configuration: .ephemeral),
        )

        do {
            let token = try await client.authenticateTransfer(
                endpoint: endpoint,
                password: "482916",
                deviceName: "Receiver",
            )
            // The receiver already had every song, so it never requests one.
            try await client.reportTransferCompletion(
                endpoint: endpoint,
                token: token,
                alreadyInLibraryTrackCount: 3,
            )
        } catch {
            await server.stop()
            throw error
        }
        await server.stop()

        let last = try #require(recorder.items.last)
        #expect(last.phase == .completed)
        #expect(last.currentTrackCount == 3)
        #expect(last.totalTrackCount == 3)
        #expect(last.receiverDeviceName == "Receiver")
        #expect(!last.isMissingTracks)
    }

    @Test
    func `receiver completion with songs it never got is reported as missing tracks`() async throws {
        let manifest = SyncManifest(
            deviceName: "Sender",
            entries: ["1111111111", "2222222222", "3333333333"].map { trackID in
                SyncManifestEntry(
                    trackID: trackID,
                    albumID: "9988776655",
                    title: "Song \(trackID)",
                    artistName: "Artist",
                    albumTitle: "Album",
                    durationSeconds: 60,
                    fileExtension: "m4a",
                )
            },
        )
        let recorder = SenderProgressRecorder()
        let server = SyncServer(
            serviceName: "Sync Server Tests",
            password: "482916",
            manifest: manifest,
            preparedFiles: [:],
            onProgress: { recorder.append($0) },
        )
        let runningServer = try await server.start()
        let endpoint = SyncEndpoint(host: "127.0.0.1", port: runningServer.port)
        let fallbackURL = try #require(URL(string: "https://fallback.example.com"))
        let client = APIClient(
            baseURL: fallbackURL,
            session: URLSession(configuration: .ephemeral),
        )

        do {
            let token = try await client.authenticateTransfer(
                endpoint: endpoint,
                password: "482916",
                deviceName: "Receiver",
            )
            // One song was already on the receiver and the other two failed
            // to download, yet the receiver still reports that it finished.
            try await client.reportTransferCompletion(
                endpoint: endpoint,
                token: token,
                alreadyInLibraryTrackCount: 1,
            )
        } catch {
            await server.stop()
            throw error
        }
        await server.stop()

        let last = try #require(recorder.items.last)
        #expect(last.phase == .completed)
        #expect(last.currentTrackCount == 1)
        #expect(last.totalTrackCount == 3)
        #expect(last.isMissingTracks)
    }

    @Test
    func `completion report still reaches the sender after the transfer task is cancelled`() async throws {
        let manifest = SyncManifest(
            deviceName: "Sender",
            entries: ["1111111111", "2222222222"].map { trackID in
                SyncManifestEntry(
                    trackID: trackID,
                    albumID: "9988776655",
                    title: "Song \(trackID)",
                    artistName: "Artist",
                    albumTitle: "Album",
                    durationSeconds: 60,
                    fileExtension: "m4a",
                )
            },
        )
        let recorder = SenderProgressRecorder()
        let server = SyncServer(
            serviceName: "Sync Server Tests",
            password: "482916",
            manifest: manifest,
            preparedFiles: [:],
            onProgress: { recorder.append($0) },
        )
        let runningServer = try await server.start()
        let endpoint = SyncEndpoint(host: "127.0.0.1", port: runningServer.port)
        let sandbox = TestLibrarySandbox()
        let session = sandbox.makeEnvironment().makeSyncTransferSession()

        do {
            let token = try await session.authenticate(
                endpoint: endpoint,
                password: "482916",
            )
            // Leaving the Transferring screen cancels the task that sends
            // the report, right after a receive that finished.
            let transferTask = Task { @MainActor in
                withUnsafeCurrentTask { $0?.cancel() }
                await session.reportTransferCompletion(
                    endpoint: endpoint,
                    token: token,
                    alreadyInLibraryTrackCount: 2,
                )
            }
            await transferTask.value
        } catch {
            await server.stop()
            throw error
        }
        await server.stop()

        let last = try #require(recorder.items.last)
        #expect(last.phase == .completed)
        #expect(last.currentTrackCount == 2)
    }

    @Test
    func `receiver completion requires a valid token`() async throws {
        let recorder = SenderProgressRecorder()
        let server = SyncServer(
            serviceName: "Sync Server Tests",
            password: "482916",
            manifest: SyncManifest(deviceName: "Sender", entries: []),
            preparedFiles: [:],
            onProgress: { recorder.append($0) },
        )
        let runningServer = try await server.start()
        let fallbackURL = try #require(URL(string: "https://fallback.example.com"))
        let client = APIClient(
            baseURL: fallbackURL,
            session: URLSession(configuration: .ephemeral),
        )

        var rejectedStatus: Int?
        do {
            try await client.reportTransferCompletion(
                endpoint: SyncEndpoint(host: "127.0.0.1", port: runningServer.port),
                token: "not-a-token",
                alreadyInLibraryTrackCount: 0,
            )
        } catch let SyncTransferError.httpFailure(statusCode, _) {
            rejectedStatus = statusCode
        }
        await server.stop()

        #expect(rejectedStatus == 401)
        #expect(!recorder.items.contains { $0.phase == .completed })
    }
}

private final nonisolated class SenderProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [SyncSenderTransferProgress] = []

    var items: [SyncSenderTransferProgress] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func append(_ progress: SyncSenderTransferProgress) {
        lock.lock()
        recorded.append(progress)
        lock.unlock()
    }
}
