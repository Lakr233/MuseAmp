@testable import AmMusic
import Testing
import UIKit

@Suite(.serialized)
@MainActor
struct TabBarControllerTests {
    @Test("Reselecting a root tab scrolls its primary scroll view to top")
    func reselectingRootTabScrollsToTop() {
        let sandbox = TestLibrarySandbox()
        let tabBar = TabBarController(environment: sandbox.makeEnvironment())
        tabBar.loadViewIfNeeded()

        let root = ScrollHostViewController()
        let navigationController = UINavigationController(rootViewController: root)
        navigationController.loadViewIfNeeded()
        root.loadViewIfNeeded()
        root.scrollView.contentInset.top = 28
        root.scrollView.contentOffset = CGPoint(x: 0, y: 180)

        tabBar.setViewControllers([navigationController], animated: false)
        tabBar.selectedViewController = navigationController

        tabBar.handleReselection(of: navigationController, animated: false)

        #expect(root.scrollView.contentOffset.y == -root.scrollView.adjustedContentInset.top)
    }

    @Test("Reselecting a nested tab pops to root then scrolls to top")
    func reselectingNestedTabPopsToRootAndScrollsToTop() {
        let sandbox = TestLibrarySandbox()
        let tabBar = TabBarController(environment: sandbox.makeEnvironment())
        tabBar.loadViewIfNeeded()

        let root = ScrollHostViewController()
        let detail = UIViewController()
        let navigationController = UINavigationController(rootViewController: root)
        navigationController.loadViewIfNeeded()
        root.loadViewIfNeeded()
        detail.loadViewIfNeeded()
        root.scrollView.contentInset.top = 20
        root.scrollView.contentOffset = CGPoint(x: 0, y: 220)
        navigationController.pushViewController(detail, animated: false)

        tabBar.setViewControllers([navigationController], animated: false)
        tabBar.selectedViewController = navigationController

        tabBar.handleReselection(of: navigationController, animated: false)

        #expect(navigationController.topViewController === root)
        #expect(root.scrollView.contentOffset.y == -root.scrollView.adjustedContentInset.top)
        #expect(navigationController.viewControllers.count == 1)
    }

    @Test("Tab bar has correct accessibility identifiers")
    func tabAccessibilityIDs() throws {
        let sandbox = TestLibrarySandbox()
        let tabBar = TabBarController(environment: sandbox.makeEnvironment())
        tabBar.loadViewIfNeeded()

        #expect(tabBar.tabBar.accessibilityIdentifier == "main.tabbar")

        if #available(iOS 18.0, *) {
            #expect(tabBar.tabs.map(\.identifier) == expectedTabIdentifiersForUITab())
            return
        }

        let vcs = try #require(tabBar.viewControllers)
        let tabIDs = vcs.map(\.tabBarItem.accessibilityIdentifier)
        #expect(tabIDs == ["tab.library", "tab.playlist", "tab.search", "tab.settings"])
    }

    @Test("Each tab wraps its root in UINavigationController with large titles")
    func navigationControllerWrapping() throws {
        let sandbox = TestLibrarySandbox()
        let tabBar = TabBarController(environment: sandbox.makeEnvironment())
        tabBar.loadViewIfNeeded()

        if #available(iOS 18.0, *) {
            let selectedControllers = materializedControllers(from: tabBar)
            #expect(selectedControllers.count == 4)

            let navControllers = try selectedControllers.map { controller in
                try #require(controller as? UINavigationController)
            }
            #expect(navControllers.map(\.navigationBar.prefersLargeTitles) == expectedLargeTitlePreferencesForUITab())
            return
        }

        let vcs = try #require(tabBar.viewControllers)
        for vc in vcs {
            let nav = try #require(vc as? UINavigationController)
            #expect(nav.navigationBar.prefersLargeTitles == true)
        }
    }

    @Test("Navigation bars have correct accessibility identifiers")
    func navAccessibilityIDs() throws {
        let sandbox = TestLibrarySandbox()
        let tabBar = TabBarController(environment: sandbox.makeEnvironment())
        tabBar.loadViewIfNeeded()

        if #available(iOS 18.0, *) {
            let navIDs = try materializedControllers(from: tabBar)
                .map { controller in
                    try #require((controller as? UINavigationController)?.navigationBar.accessibilityIdentifier)
                }
            #expect(navIDs == expectedNavigationIDsForUITab())
            return
        }

        let vcs = try #require(tabBar.viewControllers)
        let navIDs = vcs.compactMap { ($0 as? UINavigationController)?.navigationBar.accessibilityIdentifier }
        #expect(navIDs == ["nav.library", "nav.playlist", "nav.search", "nav.settings"])
    }

    @Test("Tab bar configures native popup progress")
    func configuresNativePopupBar() {
        let sandbox = TestLibrarySandbox()
        let tabBar = TabBarController(environment: sandbox.makeEnvironment())
        tabBar.loadViewIfNeeded()

        #expect(tabBar.popupBar.customBarViewController == nil)
        #expect(tabBar.popupBar.barStyle == .floating)
        #expect(tabBar.popupBar.progressViewStyle == .bottom)
    }

    @Test("Now playing controller hosts the page container")
    func nowPlayingControllerHostsPageContainer() {
        let sandbox = TestLibrarySandbox()
        let controller = NowPlayingViewController(environment: sandbox.makeEnvironment())
        controller.loadViewIfNeeded()

        #expect(controller.pageViewController.parent === controller)
        let pagesView = controller.view.subviews.first { $0.accessibilityIdentifier == "nowplaying.pages" }
        #expect(pagesView != nil)
    }

    @Test("Now playing page container centers its initial page")
    func nowPlayingPageContainerCentersInitialPage() throws {
        let controller = NowPlayingPageViewController()
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        controller.view.layoutIfNeeded()

        let scrollView = try #require(findScrollView(in: controller.view))

        #expect(scrollView.bounds.width > 0)
        #expect(scrollView.contentOffset.x == scrollView.bounds.width)
    }

    @Test("Tab bar preloads the now playing popup controller view")
    func preloadsNowPlayingPopupControllerView() throws {
        let sandbox = TestLibrarySandbox()
        let tabBar = TabBarController(environment: sandbox.makeEnvironment())
        tabBar.loadViewIfNeeded()

        let controller = try #require(tabBar.nowPlayingPopupContentViewController)
        #expect(controller.isViewLoaded)
        #expect(controller.pageViewController.parent === controller)
    }

    @Test("Tab bar starts on the library tab")
    func startsOnLibraryTab() {
        let sandbox = TestLibrarySandbox()
        let tabBar = TabBarController(environment: sandbox.makeEnvironment())
        tabBar.loadViewIfNeeded()

        #expect(tabBar.selectedIndex == 0)
    }

    @Test("Now playing prefers a hidden status bar")
    func nowPlayingPrefersHiddenStatusBar() {
        let sandbox = TestLibrarySandbox()
        let controller = NowPlayingViewController(environment: sandbox.makeEnvironment())

        #expect(controller.prefersStatusBarHidden)
    }

    @available(iOS 18.0, *)
    private func materializedControllers(from tabBar: TabBarController) -> [UIViewController] {
        (0 ..< tabBar.tabs.count).compactMap { index in
            tabBar.selectedIndex = index
            tabBar.view.layoutIfNeeded()
            return tabBar.selectedViewController
        }
    }

    @available(iOS 18.0, *)
    private func expectedTabIdentifiersForUITab() -> [String] {
        if #available(iOS 26.0, *) {
            return ["library", "playlist", "settings", "com.apple.UIKit.Search"]
        }
        return ["library", "playlist", "com.apple.UIKit.Search", "settings"]
    }

    @available(iOS 18.0, *)
    private func expectedLargeTitlePreferencesForUITab() -> [Bool] {
        if #available(iOS 26.0, *) {
            return [true, true, true, false]
        }
        return [true, true, false, true]
    }

    @available(iOS 18.0, *)
    private func expectedNavigationIDsForUITab() -> [String] {
        if #available(iOS 26.0, *) {
            return ["nav.library", "nav.playlist", "nav.settings", "nav.search"]
        }
        return ["nav.library", "nav.playlist", "nav.search", "nav.settings"]
    }

    private func findScrollView(in view: UIView) -> UIScrollView? {
        if let scrollView = view as? UIScrollView,
           scrollView.bounds.width > 0
        {
            return scrollView
        }

        for subview in view.subviews {
            if let scrollView = findScrollView(in: subview) {
                return scrollView
            }
        }

        return nil
    }
}

@MainActor
private final class ScrollHostViewController: UIViewController, TabBarReselectScrollable {
    let scrollView = UIScrollView()

    var primaryScrollViewForTabReselection: UIScrollView? {
        scrollView
    }

    override func loadView() {
        view = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        view.backgroundColor = .systemBackground
        scrollView.frame = view.bounds
        scrollView.contentSize = CGSize(width: view.bounds.width, height: 2000)
        view.addSubview(scrollView)
    }
}
