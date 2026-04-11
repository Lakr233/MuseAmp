//
//  Created by Cyandev on 2025/3/5.
//  Copyright (c) 2025 Cyandev. All rights reserved.
//

import CoreFoundation
import Testing
@testable import Choreographer

@Test @MainActor func smokeTest() async throws {
    func createPlatformVSyncObserver() throws -> VSyncObserver {
        #if canImport(AppKit) && !targetEnvironment(macCatalyst)
        return try VSyncObserver(screen: .main!)
        #else
        return try VSyncObserver()
        #endif
    }
    
    func waitForEvents(from observer: VSyncObserver) async -> CFTimeInterval {
        return await withUnsafeContinuation { cont in
            observer.frameUpdateHandler = {
                observer.frameUpdateHandler = nil
                cont.resume(returning: $0.targetTimestamp)
            }
        }
    }
    
    let observer1 = try createPlatformVSyncObserver()
    let observer2 = try createPlatformVSyncObserver()
    
    // Wait for 10 frames.
    var lastTimestamp: CFTimeInterval?
    for _ in 0..<10 {
        async let wait1 = waitForEvents(from: observer1)
        async let wait2 = waitForEvents(from: observer2)
        let timestamp1 = await wait1
        let timestamp2 = await wait2
        #expect(timestamp1 == timestamp2)
        
        if let lastTimestamp {
            print("frame interval: \((timestamp1 - lastTimestamp) * 1000)ms")
        }
        lastTimestamp = timestamp1
    }
    
    try observer1.invalidate()
    try observer2.invalidate()
    
    // All drivers should be idle when there are no observers.
    #expect(VSyncDriverManager.shared.isAllDriversIdle)
    
    // Create new observers after the driver was idle should also work.
    let observer3 = try createPlatformVSyncObserver()
    _ = await waitForEvents(from: observer3)
    try observer3.invalidate()
}
