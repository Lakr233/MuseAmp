@testable import MuseAmp
import Testing
import UIKit

@Suite(.serialized)
@MainActor
struct UIScrollViewSoftEdgeEffectTests {
    @Test
    func `shown edge effects switch to the soft style`() {
        guard #available(iOS 26.0, *) else { return }
        let scrollView = UIScrollView()

        scrollView.applySoftEdgeEffects()

        for edgeEffect in edgeEffects(of: scrollView) {
            #expect(edgeEffect.style == .soft)
            #expect(!edgeEffect.isHidden)
        }
    }

    @Test
    func `hidden edge effect stays hidden and keeps its style`() {
        guard #available(iOS 26.0, *) else { return }
        let scrollView = UIScrollView()
        scrollView.topEdgeEffect.style = .hard
        scrollView.topEdgeEffect.isHidden = true

        scrollView.applySoftEdgeEffects()

        #expect(scrollView.topEdgeEffect.isHidden)
        #expect(scrollView.topEdgeEffect.style == .hard)
        #expect(scrollView.bottomEdgeEffect.style == .soft)
        #expect(scrollView.leftEdgeEffect.style == .soft)
        #expect(scrollView.rightEdgeEffect.style == .soft)
    }

    #if targetEnvironment(macCatalyst)
        @Test
        func `relaxed now playing keeps its titlebar edge effects hidden`() {
            guard #available(iOS 26.0, *) else { return }
            let sandbox = TestLibrarySandbox()
            let controller = NowPlayingRelaxedController(environment: sandbox.makeEnvironment())
            controller.loadViewIfNeeded()

            let scrollViews: [UIScrollView] = [
                controller.centerSectionView.scrollView,
                controller.lyricTimelineView.tableView,
                controller.listSectionView.queueTableView,
            ]
            for scrollView in scrollViews {
                #expect(scrollView.topEdgeEffect.isHidden)
                #expect(!scrollView.bottomEdgeEffect.isHidden)
                #expect(scrollView.bottomEdgeEffect.style == .soft)
            }
        }
    #endif

    @available(iOS 26.0, *)
    private func edgeEffects(of scrollView: UIScrollView) -> [UIScrollEdgeEffect] {
        [
            scrollView.topEdgeEffect,
            scrollView.leftEdgeEffect,
            scrollView.bottomEdgeEffect,
            scrollView.rightEdgeEffect,
        ]
    }
}
