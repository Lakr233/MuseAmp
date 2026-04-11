//
//  Created by Cyandev on 2025/3/5.
//  Copyright (c) 2025 Cyandev. All rights reserved.
//

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit
import CoreVideo

class MacDriver: VSyncDriver {
    
    struct Request {
        
        let displayID: CGDirectDisplayID?
    }
    
    struct CoreVideoError: Error {
        
        let code: CVReturn
    }
    
    private var displayLink: CVDisplayLink?
    private let displayID: CGDirectDisplayID?
    
    required init(request: Request) throws {
        displayID = request.displayID
        
        let result = if let displayID {
            CVDisplayLinkCreateWithCGDisplay(displayID, &displayLink)
        } else {
            CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
        }
        guard result == kCVReturnSuccess, displayLink != nil else {
            throw CoreVideoError(code: result)
        }
    }
    
    func isCompatible(with request: Request) -> Bool {
        return displayID == request.displayID
    }
    
    func attach(_ callback: @MainActor @escaping (VSyncEventContext) -> Void) throws {
        guard let displayLink else {
            preconditionFailure("The display link should be created before this call")
        }
        
        var result = CVDisplayLinkSetOutputHandler(displayLink) { _, _, outputTimePtr, _, _ in
            let outputTime = outputTimePtr.pointee
            let targetTimestamp = Double(outputTime.videoTime) / Double(outputTime.videoTimeScale)
            DispatchQueue.main.async {
                callback(.init(targetTimestamp: targetTimestamp))
            }
            return kCVReturnSuccess
        }
        guard result == kCVReturnSuccess else {
            throw CoreVideoError(code: result)
        }
        
        
        result = CVDisplayLinkStart(displayLink)
        guard result == kCVReturnSuccess else {
            throw CoreVideoError(code: result)
        }
    }
    
    func detach() throws {
        guard let displayLink else {
            preconditionFailure("The display link should be created before this call")
        }
        
        var result = CVDisplayLinkStop(displayLink)
        guard result == kCVReturnSuccess else {
            throw CoreVideoError(code: result)
        }
        
        result = CVDisplayLinkSetOutputHandler(displayLink) { _, _, _, _, _ in
            return kCVReturnSuccess
        }
        guard result == kCVReturnSuccess else {
            throw CoreVideoError(code: result)
        }
    }
}

public extension VSyncObserver {
    
    /// Creates an observer for the specified screen.
    ///
    /// - Parameter screen: The screen from which VSync events are received.
    convenience init(screen: NSScreen) throws {
        self.init(__internal: ())
        
        guard let displayID = screen.deviceDescription[.init("NSScreenNumber")] as? CGDirectDisplayID else {
            fatalError("Invalid screen configuration")
        }
        try VSyncDriverManager.shared.addObserver(self, with: .init(displayID: displayID))
    }
    
    /// Creates an observer capable of being used with all active displays.
    convenience init() throws {
        self.init(__internal: ())
        
        try VSyncDriverManager.shared.addObserver(self, with: .init(displayID: nil))
    }
}
#endif
