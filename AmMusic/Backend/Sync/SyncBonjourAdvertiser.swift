//
//  SyncBonjourAdvertiser.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import Foundation

final class SyncBonjourAdvertiser: NSObject {
    private var service: NetService?

    func start(
        serviceName: String,
        deviceName: String,
        port: Int,
    ) {
        stop()

        let service = NetService(
            domain: "local.",
            type: SyncConstants.bonjourType,
            name: serviceName,
            port: Int32(port),
        )
        service.delegate = self
        service.setTXTRecord(
            NetService.data(fromTXTRecord: [
                "deviceName": Data(deviceName.utf8),
                "protocolVersion": Data(SyncConstants.protocolVersion.utf8),
            ]),
        )
        service.publish(options: [.noAutoRename])
        self.service = service
    }

    func stop() {
        service?.stop()
        service?.delegate = nil
        service = nil
    }
}

extension SyncBonjourAdvertiser: NetServiceDelegate {
    func netServiceDidPublish(_ sender: NetService) {
        AppLog.info(self, "Bonjour publish succeeded name=\(sender.name)")
    }

    func netService(_ sender: NetService, didNotPublish errorDict: [String: NSNumber]) {
        AppLog.error(self, "Bonjour publish failed name=\(sender.name) error=\(errorDict)")
    }
}
