import LNPopupController
@testable import MuseAmp
import ObjectiveC
import Testing
import UIKit

@Suite(.serialized)
@MainActor
struct PopupBarSplitViewControllerTests {
    @Test
    func `LNPopupController still exposes the split view popup bar margins hook`() {
        #expect(UISplitViewController.instancesRespond(to: PopupBarSplitViewController.popupBarMarginsSelector))
        #expect(LNPopupBar.instancesRespond(to: PopupBarSplitViewController.popupBarAppliedMarginsSelector))
        #expect(PopupBarSplitViewController.isPopupBarMarginsHookAvailable)
    }

    @Test
    func `Split view subclass replaces the LNPopupController margins hook`() {
        let selector = PopupBarSplitViewController.popupBarMarginsSelector
        let subclassIMP = class_getMethodImplementation(PopupBarSplitViewController.self, selector)
        let upstreamIMP = class_getMethodImplementation(UISplitViewController.self, selector)
        #expect(subclassIMP != upstreamIMP)
    }

    @Test
    func `Popup bar spans three fifths of the secondary column, centred`() {
        let withSidebar = PopupBarSplitViewController.popupBarMargins(
            containerWidth: 1300,
            sidebarWidth: 300,
            primaryEdge: .leading,
        )
        #expect(withSidebar.leading == 500)
        #expect(withSidebar.trailing == 200)

        let withoutSidebar = PopupBarSplitViewController.popupBarMargins(
            containerWidth: 1000,
            sidebarWidth: 0,
            primaryEdge: .leading,
        )
        #expect(withoutSidebar.leading == 200)
        #expect(withoutSidebar.trailing == 200)

        let trailingSidebar = PopupBarSplitViewController.popupBarMargins(
            containerWidth: 1300,
            sidebarWidth: 300,
            primaryEdge: .trailing,
        )
        #expect(trailingSidebar.leading == 200)
        #expect(trailingSidebar.trailing == 500)

        let unsized = PopupBarSplitViewController.popupBarMargins(
            containerWidth: 0,
            sidebarWidth: 300,
            primaryEdge: .leading,
        )
        #expect(unsized == .zero)
    }

    @Test
    func `LNPopupController applies the subclass margins to the popup bar`() throws {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first,
        )
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 1300, height: 800)
        let splitViewController = PopupBarSplitViewController(style: .doubleColumn)
        splitViewController.preferredDisplayMode = .oneBesideSecondary
        splitViewController.preferredSplitBehavior = .tile
        splitViewController.setViewController(UIViewController(), for: .primary)
        splitViewController.setViewController(UIViewController(), for: .secondary)
        window.rootViewController = splitViewController
        window.isHidden = false
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        let content = UIViewController()
        content.popupItem.title = "Song"
        splitViewController.presentPopupBar(with: content, animated: false)
        for _ in 0 ..< 100 where splitViewController.popupPresentationState != .barPresented {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        }
        #expect(splitViewController.popupPresentationState == .barPresented)
        splitViewController.view.setNeedsLayout()
        window.layoutIfNeeded()

        let bar = splitViewController.popupBar
        let appliedValue = try #require(bar.value(forKey: "_hackyMarginsInSuperviewSemanticContext") as? NSValue)
        let applied = appliedValue.directionalEdgeInsetsValue
        let expected = PopupBarSplitViewController.popupBarMargins(
            containerWidth: splitViewController.view.bounds.width,
            sidebarWidth: splitViewController.isSidebarVisible ? splitViewController.primaryColumnWidth : 0,
            primaryEdge: splitViewController.primaryEdge,
        )
        #expect(applied == expected)
        #expect(bar.frame.minX == 0)
        #expect(bar.frame.width == splitViewController.view.bounds.width)
    }
}
