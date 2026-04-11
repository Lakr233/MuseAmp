//
//  Created by Cyandev on 2025/3/5.
//  Copyright (c) 2025 Cyandev. All rights reserved.
//

import Dispatch

/// The object that manages driver instances and helps connect observers
/// to the corresponding driver.
@MainActor
class VSyncDriverManager {
    
    @MainActor
    class DriverInstanceBase {
        
        var observers: Set<VSyncObserver> = .init()
        var isAttached: Bool = false
        
        func updateState() throws { }
    }
    
    private class DriverInstance<Driver>: DriverInstanceBase where Driver: VSyncDriver {
        
        let driver: Driver
        
        init(driver: Driver) {
            self.driver = driver
        }
        
        override func updateState() throws {
            let shouldDetach = observers.isEmpty
            let isAttached = self.isAttached
            if shouldDetach && isAttached {
                try driver.detach()
                self.isAttached = false
            } else if !shouldDetach && !isAttached {
                // Note: `unowned` is okay here because the instance
                // will never be destroyed once created.
                try driver.attach { [unowned self] context in
                    self.notifyObservers(context: context)
                }
                self.isAttached = true
            }
        }
        
        private func notifyObservers(context: VSyncEventContext) {
            for observer in self.observers {
                observer.notifyFrameUpdate(context: context)
            }
        }
    }
    
    #if canImport(UIKit)
    typealias PlatformDriver = IOSDriver
    #elseif canImport(AppKit)
    typealias PlatformDriver = MacDriver
    #else
    #error("This platform is not supported.")
    #endif
    private typealias PlatformDriverInstance = DriverInstance<PlatformDriver>
    
    static let shared = VSyncDriverManager()
    
    private var driverInstances: [PlatformDriverInstance] = []
    
    #if DEBUG
    var isAllDriversIdle: Bool {
        driverInstances.lazy.filter { $0.isAttached }.isEmpty
    }
    #endif
    
    func addObserver(_ observer: VSyncObserver, with request: PlatformDriver.Request) throws {
        let instance = try compatibleOrNewDriverInstance(for: request)
        instance.observers.insert(observer)
        observer.owner = instance
        try instance.updateState()
    }
    
    func removeObserver(_ observer: VSyncObserver) throws {
        guard let ownerDriverInstance = observer.owner else {
            return
        }
        ownerDriverInstance.observers.remove(observer)
        try ownerDriverInstance.updateState()
    }
    
    private func compatibleOrNewDriverInstance(
        for request: PlatformDriver.Request
    ) throws -> PlatformDriverInstance {
        let existingInstance = driverInstances
            .filter({ $0.driver.isCompatible(with: request) })
            .first
        if let existingInstance {
            return existingInstance
        }
        
        let newDriver = try PlatformDriver(request: request)
        let newInstance = DriverInstance(driver: newDriver)
        driverInstances.append(newInstance)
        return newInstance
    }
}
