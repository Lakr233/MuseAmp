@testable import MuseAmp
import Testing
import UIKit

@Suite(.serialized)
@MainActor
struct MainControllerTests {
    @Test
    func `Relaxed and Catalyst layouts do not build the compact tab shell`() {
        let sandbox = TestLibrarySandbox()
        let mainController = MainController(environment: sandbox.makeEnvironment())
        mainController.loadViewIfNeeded()

        mainController.transitionToMode(.relaxed)
        #expect(mainController.compactTabBarControllerIfLoaded == nil)

        mainController.transitionToMode(.catalyst)
        #expect(mainController.compactTabBarControllerIfLoaded == nil)
    }

    @Test
    func `A size-class round trip keeps the tab shell but rebuilds its Now Playing`() throws {
        let sandbox = TestLibrarySandbox()
        let environment = sandbox.makeEnvironment()
        let mainController = MainController(environment: environment)
        mainController.loadViewIfNeeded()

        weak var releasedNowPlaying: NowPlayingCompactController?
        let tabShell: TabBarController = try autoreleasepool {
            mainController.transitionToMode(.compact)
            let tabShell = try #require(mainController.compactTabBarControllerIfLoaded)
            releasedNowPlaying = tabShell.nowPlayingPopupContentViewController
            #expect(releasedNowPlaying != nil)

            mainController.transitionToMode(.relaxed)
            return tabShell
        }

        #expect(mainController.compactTabBarControllerIfLoaded === tabShell)
        #expect(tabShell.parent == nil)
        #expect(releasedNowPlaying == nil)

        tabShell.updateNowPlayingPopupItem(using: environment.playbackController.snapshot)
        tabShell.prepareNowPlayingPopupContentViewController()
        #expect(tabShell.nowPlayingPopupContentViewController == nil)

        mainController.transitionToMode(.compact)

        #expect(mainController.compactTabBarControllerIfLoaded === tabShell)
        #expect(tabShell.parent === mainController)
        let rebuiltNowPlaying = try #require(tabShell.nowPlayingPopupContentViewController)
        #expect(rebuiltNowPlaying.isViewLoaded)
    }
}

#if targetEnvironment(macCatalyst)
    @Suite(.serialized)
    @MainActor
    struct MainControllerTitlebarInsetTests {
        @Test
        func `Detail content starts right under its navigation bar after the sidebar is hidden and shown`() throws {
            let sandbox = TestLibrarySandbox()
            let mainController = MainController(environment: sandbox.makeEnvironment())
            let scene = try #require(
                UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first,
            )
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 1200, height: 800)
            // Stands in for the top inset the hidden title bar reserves.
            mainController.additionalSafeAreaInsets.top = 31
            window.rootViewController = mainController
            window.isHidden = false
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }
            window.layoutIfNeeded()

            let navigationController = try #require(mainController.activeContentNavigationController)
            let content = try #require(navigationController.topViewController)
            let navigationBar = navigationController.navigationBar
            func barBottom() -> CGFloat {
                navigationBar.convert(navigationBar.bounds, to: content.view).maxY
            }
            func gapBelowBar() -> CGFloat {
                content.view.safeAreaInsets.top - barBottom()
            }

            mainController.updateDetailColumnTitlebarInset(sidebarVisible: true)
            window.layoutIfNeeded()
            let sidebarShownBarBottom = barBottom()
            #expect(abs(gapBelowBar()) < 0.5)

            mainController.updateDetailColumnTitlebarInset(sidebarVisible: false)
            window.layoutIfNeeded()
            #expect(barBottom() > sidebarShownBarBottom)
            #expect(abs(gapBelowBar()) < 0.5)

            mainController.updateDetailColumnTitlebarInset(sidebarVisible: true)
            window.layoutIfNeeded()
            #expect(barBottom() == sidebarShownBarBottom)
            #expect(abs(gapBelowBar()) < 0.5)
        }
    }

    @Suite(.serialized)
    @MainActor
    struct MainControllerSidebarToggleTests {
        @Test
        func `The title bar toggle hides the sidebar and brings it back`() throws {
            let sandbox = TestLibrarySandbox()
            let mainController = MainController(environment: sandbox.makeEnvironment())
            let scene = try #require(
                UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first,
            )
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 1200, height: 800)
            window.rootViewController = mainController
            window.isHidden = false
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }
            window.layoutIfNeeded()

            let splitViewController = mainController.rootSplitViewController
            let toggle = mainController.sidebarToggleButton
            func toggleFrame() -> CGRect {
                toggle.convert(toggle.bounds, to: window)
            }
            #expect(splitViewController.isSidebarVisible)
            #expect(toggle.window === window)
            let sidebarWidth = splitViewController.primaryColumnWidth
            let shownFrame = toggleFrame()
            #expect(shownFrame.maxX <= sidebarWidth)
            #expect(shownFrame.maxX >= sidebarWidth - 24)

            toggle.sendActions(for: .touchUpInside)
            window.layoutIfNeeded()
            #expect(!splitViewController.isSidebarVisible)
            #expect(toggle.window === window)
            #expect(!toggle.isHidden)
            #expect(window.bounds.contains(toggleFrame()))
            #expect(toggleFrame().minX < shownFrame.minX)

            toggle.sendActions(for: .touchUpInside)
            window.layoutIfNeeded()
            #expect(splitViewController.isSidebarVisible)
            #expect(toggleFrame() == shownFrame)
        }
    }
#endif

struct SidebarHeaderModeTests {
    @Test
    func `Library and Playlists get headers when Search is hidden`() {
        let sections: [SidebarSection] = [.library, .playlists, .settings]

        let modes = sections.indices.map {
            SidebarViewController.headerMode(forSectionAt: $0, in: sections)
        }

        #expect(modes == [.supplementary, .supplementary, .none])
    }

    @Test
    func `Library and Playlists get headers when Search is shown`() {
        let sections: [SidebarSection] = [.navigation, .library, .playlists, .settings]

        let modes = sections.indices.map {
            SidebarViewController.headerMode(forSectionAt: $0, in: sections)
        }

        #expect(modes == [.none, .supplementary, .supplementary, .none])
    }

    @Test
    func `Sections outside the snapshot get no header`() {
        #expect(SidebarViewController.headerMode(forSectionAt: 0, in: []) == .none)
        #expect(SidebarViewController.headerMode(forSectionAt: 4, in: [.library]) == .none)
    }
}
