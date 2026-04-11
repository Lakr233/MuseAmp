@testable import AmMusic
import Testing

struct SyncEndpointParserTests {
    @Test
    func `parses hostname and port`() throws {
        let endpoint = try SyncEndpoint.parse("speaker-room.local:52301")
        #expect(endpoint.host == "speaker-room.local")
        #expect(endpoint.port == 52301)
        #expect(endpoint.displayString == "speaker-room.local:52301")
    }

    @Test
    func `parses ipv4 and port`() throws {
        let endpoint = try SyncEndpoint.parse("192.168.1.10:52301")
        #expect(endpoint.host == "192.168.1.10")
        #expect(endpoint.port == 52301)
    }

    @Test
    func `parses bracketed ipv6 and port`() throws {
        let endpoint = try SyncEndpoint.parse("[fd12::12]:52301")
        #expect(endpoint.host == "fd12::12")
        #expect(endpoint.port == 52301)
        #expect(endpoint.displayString == "[fd12::12]:52301")
    }

    @Test
    func `rejects malformed address`() {
        #expect(throws: SyncEndpointParseError.self) {
            _ = try SyncEndpoint.parse("fd12::12:52301")
        }
    }
}
