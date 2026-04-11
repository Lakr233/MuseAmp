//
//  Created by Cyandev on 2025/3/5.
//  Copyright (c) 2025 Cyandev. All rights reserved.
//

/// An abstraction of the VSync driver on each platform.
@MainActor
protocol VSyncDriver {
    
    /// A type that describes the sync request.
    associatedtype Request
    
    /// Creates the driver with a request.
    init(request: Request) throws
    
    /// Determines whether this driver instance is compatible with
    /// the specified request.
    ///
    /// Clients can reuse the same driver instance for multiple
    /// compatible requests to reduce the cost of system resources.
    func isCompatible(with request: Request) -> Bool
    
    /// Attaches a callback to receive update notifications from the
    /// driver.
    ///
    /// This method should detach the existing callback before
    /// attaching the new one.
    func attach(
        _ callback: @MainActor @escaping (VSyncEventContext) -> Void
    ) throws
    
    /// Detaches the attached callback and release system resources.
    func detach() throws
}
