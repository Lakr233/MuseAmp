//
//  SyncBonjourBrowser.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import Foundation

@MainActor
final class SyncBonjourBrowser: NSObject {
    var onDevicesChanged: (([DiscoveredDevice]) -> Void) = { _ in }

    private let browser = NetServiceBrowser()
    private var servicesByName: [String: NetService] = [:]
    private(set) var devicesByName: [String: DiscoveredDevice] = [:]
    private var isSearching = false

    override init() {
        super.init()
        browser.delegate = self
    }

    var devices: [DiscoveredDevice] {
        devicesByName.values.sorted { lhs, rhs in
            if lhs.deviceName == rhs.deviceName {
                return lhs.serviceName.localizedCaseInsensitiveCompare(rhs.serviceName) == .orderedAscending
            }
            return lhs.deviceName.localizedCaseInsensitiveCompare(rhs.deviceName) == .orderedAscending
        }
    }

    func start() {
        guard !isSearching else {
            return
        }
        isSearching = true
        browser.searchForServices(
            ofType: SyncConstants.bonjourType,
            inDomain: "local.",
        )
    }

    func stop() {
        guard isSearching || !servicesByName.isEmpty else {
            return
        }
        isSearching = false
        browser.stop()
        for service in servicesByName.values {
            service.stop()
            service.delegate = nil
        }
        servicesByName.removeAll()
        devicesByName.removeAll()
        notify()
    }

    func resolveService(named serviceName: String) async -> DiscoveredDevice? {
        if let cached = devicesByName[serviceName] {
            return cached
        }

        let resolver = NetServiceResolver(
            service: NetService(
                domain: "local.",
                type: SyncConstants.bonjourType,
                name: serviceName,
            ),
        )
        let resolved = await resolver.resolve()
        if let resolved {
            devicesByName[serviceName] = resolved
            notify()
        }
        return resolved
    }
}

private extension SyncBonjourBrowser {
    func updateDevice(for service: NetService) {
        guard let device = Self.makeDiscoveredDevice(from: service) else {
            AppLog.warning(self, "updateDevice missing endpoint name=\(service.name)")
            return
        }
        devicesByName[service.name] = device
        notify()
    }

    func notify() {
        onDevicesChanged(devices)
    }

    static func makeDiscoveredDevice(from service: NetService) -> DiscoveredDevice? {
        let endpoints = makeEndpoints(from: service)
        let hostName = service.hostName.map(SyncEndpoint.normalizeHost(_:))
        let preferredEndpoint = hostName.map { SyncEndpoint(host: $0, port: service.port) }
            ?? endpoints.first
        let deviceName = makeTXTRecordValue(named: "deviceName", from: service.txtRecordData()) ?? service.name
        return DiscoveredDevice(
            serviceName: service.name,
            deviceName: deviceName,
            preferredEndpoint: preferredEndpoint,
            fallbackEndpoints: endpoints,
            port: service.port,
        )
    }

    static func makeTXTRecordValue(
        named key: String,
        from data: Data?,
    ) -> String? {
        guard let data,
              let value = NetService.dictionary(fromTXTRecord: data)[key]
        else {
            return nil
        }
        return String(data: value, encoding: .utf8)
    }

    static func makeEndpoints(from service: NetService) -> [SyncEndpoint] {
        var endpoints: [SyncEndpoint] = []
        var seen = Set<SyncEndpoint>()

        if let hostName = service.hostName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !hostName.isEmpty
        {
            let endpoint = SyncEndpoint(host: hostName, port: service.port)
            endpoints.append(endpoint)
            seen.insert(endpoint)
        }

        for address in service.addresses ?? [] {
            guard let endpoint = makeEndpoint(from: address, port: service.port),
                  !seen.contains(endpoint)
            else {
                continue
            }
            endpoints.append(endpoint)
            seen.insert(endpoint)
        }

        return endpoints
    }

    static func makeEndpoint(
        from addressData: Data,
        port: Int,
    ) -> SyncEndpoint? {
        addressData.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress?.assumingMemoryBound(to: sockaddr.self) else {
                return nil
            }

            let family = baseAddress.pointee.sa_family
            guard family == UInt8(AF_INET) || family == UInt8(AF_INET6) else {
                return nil
            }

            var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let length = family == UInt8(AF_INET)
                ? socklen_t(MemoryLayout<sockaddr_in>.size)
                : socklen_t(MemoryLayout<sockaddr_in6>.size)
            let result = getnameinfo(
                baseAddress,
                length,
                &hostBuffer,
                socklen_t(hostBuffer.count),
                nil,
                0,
                NI_NUMERICHOST,
            )
            guard result == 0 else {
                return nil
            }

            return SyncEndpoint(
                host: String(cString: hostBuffer),
                port: port,
            )
        }
    }

    final class NetServiceResolver: NSObject, NetServiceDelegate {
        private let service: NetService
        private var continuation: CheckedContinuation<DiscoveredDevice?, Never>?

        init(service: NetService) {
            self.service = service
            super.init()
            service.delegate = self
        }

        func resolve() async -> DiscoveredDevice? {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                service.resolve(withTimeout: 5)
            }
        }

        func netServiceDidResolveAddress(_ sender: NetService) {
            continuation?.resume(
                returning: SyncBonjourBrowser.makeDiscoveredDevice(from: sender),
            )
            continuation = nil
        }

        func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
            AppLog.warning(self, "resolve failed name=\(sender.name) error=\(errorDict)")
            continuation?.resume(returning: nil)
            continuation = nil
        }
    }
}

extension SyncBonjourBrowser: NetServiceBrowserDelegate, NetServiceDelegate {
    func netServiceBrowserWillSearch(_ browser: NetServiceBrowser) {
        AppLog.info(self, "Bonjour browser started \(browser)")
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        AppLog.error(self, "Bonjour browser failed \(browser) error=\(errorDict)")
    }

    func netServiceBrowser(
        _: NetServiceBrowser,
        didFind service: NetService,
        moreComing: Bool,
    ) {
        AppLog.verbose(self, "Bonjour found service name=\(service.name)")
        servicesByName[service.name] = service
        service.delegate = self
        service.resolve(withTimeout: 5)
        if !moreComing {
            notify()
        }
    }

    func netServiceBrowser(
        _: NetServiceBrowser,
        didRemove service: NetService,
        moreComing: Bool,
    ) {
        AppLog.verbose(self, "Bonjour removed service name=\(service.name)")
        servicesByName.removeValue(forKey: service.name)
        devicesByName.removeValue(forKey: service.name)
        service.stop()
        service.delegate = nil
        if !moreComing {
            notify()
        }
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        updateDevice(for: sender)
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        AppLog.warning(self, "Bonjour resolve failed name=\(sender.name) error=\(errorDict)")
    }
}
