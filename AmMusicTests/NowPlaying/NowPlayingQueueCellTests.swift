@testable import AmMusic
import Testing
import UIKit

@Suite(.serialized)
@MainActor
struct NowPlayingQueueCellTests {
    // MARK: - TableBaseCell selection background

    @Test
    func `TableBaseCell hides selectedBackgroundView on init`() {
        let cell = TableBaseCell(style: .default, reuseIdentifier: "test")
        #expect(cell.selectedBackgroundView != nil)
        #expect(cell.selectedBackgroundView?.isHidden == true || cell.selectedBackgroundView?.backgroundColor == nil)
    }

    @Test
    func `TableBaseCell suppresses selection background after setSelected`() {
        let cell = TableBaseCell(style: .default, reuseIdentifier: "test")
        cell.setSelected(true, animated: false)
        #expect(cell.selectedBackgroundView?.isHidden == true)
    }

    @Test
    func `TableBaseCell suppresses highlight background after setHighlighted`() {
        let cell = TableBaseCell(style: .default, reuseIdentifier: "test")
        cell.setHighlighted(true, animated: false)
        #expect(cell.selectedBackgroundView?.isHidden == true)
    }

    @Test
    func `TableBaseCell clears selection background after prepareForReuse`() {
        let cell = TableBaseCell(style: .default, reuseIdentifier: "test")
        cell.setSelected(true, animated: false)
        cell.prepareForReuse()
        cell.setSelected(true, animated: false)
        #expect(cell.selectedBackgroundView?.isHidden == true)
    }

    @Test
    func `NowPlayingQueueTrackCell inherits selection suppression`() {
        let cell = NowPlayingQueueTrackCell(style: .default, reuseIdentifier: NowPlayingQueueTrackCell.reuseID)
        cell.setSelected(true, animated: false)
        #expect(cell.selectedBackgroundView?.isHidden == true)
    }

    @Test
    func `NowPlayingQueueEmptyCell inherits selection suppression`() {
        let cell = NowPlayingQueueEmptyCell(style: .default, reuseIdentifier: NowPlayingQueueEmptyCell.reuseID)
        cell.setSelected(true, animated: false)
        #expect(cell.selectedBackgroundView?.isHidden == true)
    }

    @Test
    func `NowPlayingQueueFooterCell inherits selection suppression`() {
        let cell = NowPlayingQueueFooterCell(style: .default, reuseIdentifier: NowPlayingQueueFooterCell.reuseID)
        cell.setSelected(true, animated: false)
        #expect(cell.selectedBackgroundView?.isHidden == true)
    }

    // MARK: - Queue spacer heights

    @Test
    func `Queue header spacer height is 100`() {
        #expect(NowPlayingListSectionView.Layout.headerSpacerHeight == 100)
    }

    @Test
    func `Queue footer spacer height is 100`() {
        #expect(NowPlayingListSectionView.Layout.footerSpacerHeight == 100)
    }
}
