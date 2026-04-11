//
//  Created by Cyandev on 2025/3/5.
//  Copyright (c) 2025 Cyandev. All rights reserved.
//

#if canImport(UIKit)
import Combine
import QuartzCore
import UIKit

class IOSDriver: NSObject, VSyncDriver {
    
    struct Request { }
    
    private var displayLink: CADisplayLink?
    private var callback: (@MainActor (VSyncEventContext) -> Void)?
    private var cancellables: Set<AnyCancellable> = .init()
    
    required init(request: Request) throws {
        super.init()
        
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                self?.invalidateDisplayLink()
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.prepareDisplayLinkIfNeeded()
            }
            .store(in: &cancellables)
    }
    
    func isCompatible(with request: Request) -> Bool {
        return true
    }
    
    func attach(_ callback: @MainActor @escaping (VSyncEventContext) -> Void) throws {
        self.callback = callback
        prepareDisplayLinkIfNeeded()
    }
    
    func detach() throws {
        invalidateDisplayLink()
        callback = nil
    }
    
    @objc private func handleDisplayLinkEvent() {
        if let callback, let displayLink {
            callback(.init(targetTimestamp: displayLink.targetTimestamp))
        }
    }
    
    private func prepareDisplayLinkIfNeeded() {
        guard callback != nil, displayLink == nil else {
            return
        }
        
        let displayLink = CADisplayLink(target: self, selector: #selector(handleDisplayLinkEvent))
        if #available(iOS 15.0, tvOS 15.0, *) {
            displayLink.preferredFrameRateRange = .init(minimum: 80, maximum: 120, preferred: 120)
        }
        displayLink.add(to: .main, forMode: .common)
        self.displayLink = displayLink
    }
    
    private func invalidateDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }
}

public extension VSyncObserver {
    
    /// Creates an observer with the default configuration.
    convenience init() throws {
        self.init(__internal: ())
        
        try VSyncDriverManager.shared.addObserver(self, with: .init())
    }
}
#endif
