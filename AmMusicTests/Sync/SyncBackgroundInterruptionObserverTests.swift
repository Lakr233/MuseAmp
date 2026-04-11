@testable import AmMusic
import Testing
import UIKit

@Suite(.serialized)
@MainActor
struct SyncBackgroundInterruptionObserverTests {
    @Test
    func `permission prompt inactive transition does not interrupt sync`() {
        let notificationCenter = NotificationCenter()
        var interruptionCount = 0
        let observer = SyncBackgroundInterruptionObserver(notificationCenter: notificationCenter) {
            interruptionCount += 1
        }

        observer.start()
        notificationCenter.post(name: UIApplication.willResignActiveNotification, object: nil)

        #expect(interruptionCount == 0)

        notificationCenter.post(name: UIApplication.didEnterBackgroundNotification, object: nil)

        #expect(interruptionCount == 1)
    }

    @Test
    func `stopping observer ignores later background transitions`() {
        let notificationCenter = NotificationCenter()
        var interruptionCount = 0
        let observer = SyncBackgroundInterruptionObserver(notificationCenter: notificationCenter) {
            interruptionCount += 1
        }

        observer.start()
        observer.stop()
        notificationCenter.post(name: UIApplication.didEnterBackgroundNotification, object: nil)

        #expect(interruptionCount == 0)
    }
}
