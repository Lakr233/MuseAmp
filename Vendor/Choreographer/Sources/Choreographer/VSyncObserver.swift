//
//  Created by Cyandev on 2025/3/5.
//  Copyright (c) 2025 Cyandev. All rights reserved.
//

import CoreFoundation

/// A type that represents the context of a VSync event.
public struct VSyncEventContext: Sendable {
    
    /// The time interval that represents when the next frame displays.
    public let targetTimestamp: CFTimeInterval
}

/// An observer of VSync events from the display.
///
/// The observer emits VSync events immediately after it's created, and
/// will be internally retained until being invalidated. You must call
/// ``invalidate()`` method after you've finished using it, otherwise it
/// will leak.
@MainActor
public class VSyncObserver {
    
    weak var owner: VSyncDriverManager.DriverInstanceBase?
    
    /// The closure that is invoked to update a frame.
    public var frameUpdateHandler: (@MainActor (VSyncEventContext) -> Void)?
    
    /// A dummy initializer to prevent clients from creating observers
    /// directly without the platform-specific initializers.
    init(__internal: ()) { }
    
    /// Stops the observer.
    ///
    /// ``frameUpdateHandler`` will never be invoked again, and related
    /// system resources might be released.
    public func invalidate() throws {
        frameUpdateHandler = nil
        try VSyncDriverManager.shared.removeObserver(self)
    }
    
    func notifyFrameUpdate(context: VSyncEventContext) {
        frameUpdateHandler?(context)
    }
}

extension VSyncObserver: Hashable {
    
    public nonisolated static func == (
        lhs: VSyncObserver, rhs: VSyncObserver
    ) -> Bool {
        return lhs === rhs
    }
    
    public nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}
