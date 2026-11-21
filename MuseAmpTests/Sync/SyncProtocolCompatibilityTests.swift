import Foundation
@testable import MuseAmp
import Testing

struct SyncProtocolCompatibilityTests {
    @Test
    func `catalog transfers keep protocol four while local transfers require five`() throws {
        let catalog = entry(trackID: "123", albumID: "456")
        let localTrack = entry(trackID: "local-track-" + String(repeating: "a", count: 64), albumID: "456")
        let localAlbum = entry(trackID: "123", albumID: "local-album-" + String(repeating: "b", count: 64))
        #expect(SyncManifest(deviceName: "Sender", entries: [catalog]).protocolVersion == "4")
        for entries in [[localTrack], [catalog, localTrack], [localAlbum]] {
            let manifest = SyncManifest(deviceName: "Sender", entries: entries)
            #expect(manifest.protocolVersion == "5")
            #expect(SyncConstants.isCompatible(protocolVersion: manifest.protocolVersion, entries: entries))
            #expect(!SyncConstants.isCompatible(protocolVersion: "4", entries: entries))
            // Protocol-four receivers compare the version for exact equality.
            #expect(manifest.protocolVersion != "4")
            let decoded = try JSONDecoder().decode(SyncManifest.self, from: JSONEncoder().encode(manifest))
            #expect(decoded.protocolVersion == "5")
        }
        #expect(SyncConstants.isCompatible(protocolVersion: "4", entries: [catalog]))
        #expect(SyncConstants.isCompatible(protocolVersion: "5", entries: [catalog]))
        #expect(!SyncConstants.isCompatible(protocolVersion: "6", entries: [catalog]))
    }

    private func entry(trackID: String, albumID: String) -> SyncManifestEntry {
        SyncManifestEntry(trackID: trackID, albumID: albumID, title: "Song", artistName: "Artist", albumTitle: "Album", durationSeconds: 2, fileExtension: "m4a")
    }

    @Test
    func `bonjour identity produces unique advertised names and local display names`() {
        let token = "A1B2C3"
        let serviceName = SyncBonjourIdentity.makeAdvertisedServiceName(
            baseName: "Living Room Apple TV",
            token: token,
        )
        let deviceName = SyncBonjourIdentity.makeAdvertisedDeviceName(
            baseName: "Living Room Apple TV",
            token: token,
        )

        #expect(serviceName == "Living Room Apple TV-A1B2C3")
        #expect(deviceName == "Living Room Apple TV [A1B2C3]")

        let discovered = DiscoveredDevice(
            serviceName: serviceName,
            deviceName: deviceName,
            protocolVersion: SyncConstants.protocolVersion,
            role: .receiver,
            preferredEndpoint: SyncEndpoint(host: "living-room.local", port: 4040),
            fallbackEndpoints: [],
            port: 4040,
        )
        let handshake = SyncReceiverHandshakeInfo(
            serviceName: serviceName,
            deviceName: deviceName,
            pairingCode: "048271",
        )

        #expect(discovered.bonjourServiceDisplayName == serviceName + ".local")
        #expect(handshake.bonjourServiceDisplayName == serviceName + ".local")
    }

    @Test
    func `bonjour service name stays within net service limit`() {
        let baseName = String(repeating: "客厅AppleTV", count: 12)
        let serviceName = SyncBonjourIdentity.makeAdvertisedServiceName(
            baseName: baseName,
            token: "ABC123",
        )

        #expect(serviceName.lengthOfBytes(using: .utf8) <= 63)
        #expect(serviceName.hasSuffix("-ABC123"))
    }

    @Test
    func `discovered device is compatible only when protocol version matches current app`() {
        let compatible = DiscoveredDevice(
            serviceName: "Living Room",
            deviceName: "Living Room Apple TV",
            protocolVersion: SyncConstants.protocolVersion,
            role: .receiver,
            preferredEndpoint: SyncEndpoint(host: "living-room.local", port: 4040),
            fallbackEndpoints: [],
            port: 4040,
        )
        let legacy = DiscoveredDevice(
            serviceName: "Legacy Room",
            deviceName: "Legacy Apple TV",
            protocolVersion: "2",
            role: .receiver,
            preferredEndpoint: SyncEndpoint(host: "legacy-room.local", port: 4040),
            fallbackEndpoints: [],
            port: 4040,
        )
        let unknown = DiscoveredDevice(
            serviceName: "Unknown Room",
            deviceName: "Unknown Apple TV",
            protocolVersion: nil,
            role: .receiver,
            preferredEndpoint: SyncEndpoint(host: "unknown-room.local", port: 4040),
            fallbackEndpoints: [],
            port: 4040,
        )

        #expect(compatible.isCompatibleProtocolVersion)
        #expect(legacy.isCompatibleProtocolVersion == false)
        #expect(unknown.isCompatibleProtocolVersion == false)
    }

    @Test
    func `connection info defaults to current protocol version and decodes legacy payloads`() throws {
        let current = SyncConnectionInfo(
            serviceName: "iPhone",
            password: "482916",
            deviceName: "My iPhone",
            fallbackEndpoints: [SyncEndpoint(host: "iphone.local", port: 8080)],
        )
        #expect(current.protocolVersion == SyncConstants.protocolVersion)

        let legacyPayload = """
        {
          "serviceName": "Old iPhone",
          "password": "482916",
          "deviceName": "Old iPhone",
          "fallbackEndpoints": [
            {
              "host": "old-iphone.local",
              "port": 8080
            }
          ]
        }
        """
        let decoded = try JSONDecoder().decode(
            SyncConnectionInfo.self,
            from: Data(legacyPayload.utf8),
        )

        #expect(decoded.protocolVersion == nil)
        #expect(decoded.deviceName == "Old iPhone")
        #expect(decoded.fallbackEndpoints.first?.host == "old-iphone.local")
    }

    @Test
    func `receiver handshake info pairing code survives JSON round-trip`() throws {
        let original = SyncReceiverHandshakeInfo(
            serviceName: "Apple TV",
            deviceName: "Living Room Apple TV",
            pairingCode: "048271",
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(original)
        let decoded = try JSONDecoder().decode(SyncReceiverHandshakeInfo.self, from: data)

        #expect(decoded.pairingCode == "048271")
        #expect(decoded.serviceName == original.serviceName)
        #expect(decoded.deviceName == original.deviceName)
        #expect(decoded.protocolVersion == SyncConstants.protocolVersion)
    }

    @Test
    func `receiver handshake info pairing code survives base64 URL round-trip`() throws {
        let original = SyncReceiverHandshakeInfo(
            serviceName: "Apple TV",
            deviceName: "Living Room Apple TV",
            pairingCode: "048271",
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let jsonData = try encoder.encode(original)
        let base64 = jsonData.base64EncodedString()

        var components = URLComponents()
        components.scheme = "museamp"
        components.host = "tv"
        components.queryItems = [URLQueryItem(name: "data", value: base64)]
        let url = try #require(components.url)

        let parsed = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let extractedBase64 = try #require(parsed?.queryItems?.first(where: { $0.name == "data" })?.value)
        let decodedData = try #require(Data(base64Encoded: extractedBase64))
        let decoded = try JSONDecoder().decode(SyncReceiverHandshakeInfo.self, from: decodedData)

        #expect(decoded.pairingCode == "048271")
    }

    @Test
    func `receiver handshake info without pairing code decodes with nil`() throws {
        let payload = """
        {
          "serviceName": "Apple TV",
          "deviceName": "Apple TV",
          "protocolVersion": "3"
        }
        """
        let decoded = try JSONDecoder().decode(
            SyncReceiverHandshakeInfo.self,
            from: Data(payload.utf8),
        )

        #expect(decoded.pairingCode == nil)
        #expect(decoded.protocolVersion == "3")
    }
}
