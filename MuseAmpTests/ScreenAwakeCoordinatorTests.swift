import Foundation
@testable import MuseAmp
import Testing

@Suite(.serialized)
struct ScreenAwakeCoordinatorTests {
    @Test
    func `repeated acquires by one screen are released by one release`() {
        let coordinator = ScreenAwakeCoordinator()
        let screen = NSObject()

        // A cancelled swipe-back calls viewWillAppear again with no
        // viewDidDisappear in between.
        coordinator.acquire(.syncSession, owner: screen)
        coordinator.acquire(.syncSession, owner: screen)
        coordinator.release(.syncSession, owner: screen)

        #expect(!coordinator.isHolding(.syncSession))
    }

    @Test
    func `each screen keeps its own hold`() {
        let coordinator = ScreenAwakeCoordinator()
        let sendingScreen = NSObject()
        let transferringScreen = NSObject()

        coordinator.acquire(.syncSession, owner: sendingScreen)
        coordinator.acquire(.syncSession, owner: transferringScreen)
        coordinator.release(.syncSession, owner: sendingScreen)
        #expect(coordinator.isHolding(.syncSession))

        coordinator.release(.syncSession, owner: transferringScreen)
        #expect(!coordinator.isHolding(.syncSession))
    }

    @Test
    func `release without a matching acquire leaves other holds alone`() {
        let coordinator = ScreenAwakeCoordinator()
        let screen = NSObject()

        coordinator.acquire(.downloadsActive)
        coordinator.release(.downloadsActive, owner: screen)
        coordinator.release(.syncSession, owner: screen)

        #expect(coordinator.isHolding(.downloadsActive))
        coordinator.release(.downloadsActive)
        #expect(!coordinator.isHolding(.downloadsActive))
    }
}
