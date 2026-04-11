//
//  NetworkMonitor.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import Combine
import Network

@MainActor
final class NetworkMonitor {
    enum ConnectionType: Equatable {
        case wifi
        case cellular
        case none
    }

    let connectionTypePublisher = CurrentValueSubject<ConnectionType, Never>(.none)

    var connectionType: ConnectionType {
        connectionTypePublisher.value
    }

    var isWiFi: Bool {
        connectionType == .wifi
    }

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "app.network-monitor")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let type: ConnectionType = if path.status != .satisfied {
                .none
            } else if path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet) {
                .wifi
            } else if path.usesInterfaceType(.cellular) {
                .cellular
            } else {
                .wifi
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard connectionTypePublisher.value != type else { return }
                connectionTypePublisher.send(type)
            }
        }
        monitor.start(queue: monitorQueue)
    }

    deinit {
        monitor.cancel()
    }
}
