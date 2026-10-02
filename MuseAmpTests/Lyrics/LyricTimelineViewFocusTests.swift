@testable import MuseAmp
import Testing
import UIKit

@Suite(.serialized)
@MainActor
struct LyricTimelineViewFocusTests {
    @Test
    func `the active line settles at its anchor once the rows above it are measured`() async throws {
        let sandbox = TestLibrarySandbox()
        let view = LyricTimelineView(environment: sandbox.makeEnvironment())
        view.frame = CGRect(x: 0, y: 0, width: 320, height: 600)
        view.layoutIfNeeded()
        // Let the binding's initial snapshot (no track playing) land first.
        try await Task.sleep(for: .milliseconds(200))

        let wrappingText = String(repeating: "a lyric line long enough to wrap ", count: 6)
        let activeLine = 12
        var items: [LyricTimelineView.Item] = [.spacer(LyricTimelineView.Layout.topContentInset)]
        for index in 0 ..< 24 {
            items.append(.line(index, "\(index) \(wrappingText)", index == activeLine))
        }
        items.append(.spacer(LyricTimelineView.Layout.bottomContentInset))
        view.applySnapshot(LyricTimelineView.Snapshot(items: items))
        view.focusCurrentLine(isUserInitialed: false)

        let activeRow = IndexPath(row: activeLine + 1, section: 0)
        let tableView = view.tableView
        let anchorY = tableView.bounds.height * LyricTimelineView.Layout.activeLineAnchorFraction
        func distanceFromAnchor() -> CGFloat {
            view.layoutIfNeeded()
            let rowRect = tableView.rectForRow(at: activeRow)
            return abs(rowRect.midY - tableView.contentOffset.y - anchorY)
        }

        var attempts = 0
        while distanceFromAnchor() > 6, attempts < 40 {
            attempts += 1
            try await Task.sleep(for: .milliseconds(50))
        }
        try await Task.sleep(for: .milliseconds(300))

        #expect(tableView.rectForRow(at: activeRow).height > tableView.estimatedRowHeight * 2)
        #expect(distanceFromAnchor() <= 6)
    }
}
