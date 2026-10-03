import SnapKit
import UIKit

@MainActor
class NowPlayingPagingSectionView: UIView {
    private nonisolated enum Page: Int, CaseIterable {
        case queue
        case artwork
        case lyrics
    }

    private nonisolated enum Animation {
        static let duration: TimeInterval = 0.9
        static let damping: CGFloat = 1.02
        static let initialVelocity: CGFloat = 0.78
    }

    private final class PagingScrollView: UIScrollView {
        override func touchesShouldCancel(in _: UIView) -> Bool {
            true
        }
    }

    var onPageChanged: (NowPlayingControlIslandViewModel.ContentSelector) -> Void = { _ in }

    /// Emits 0 when centered on the artwork page, 1 when fully on queue or lyrics.
    var onArtworkPageDistance: (CGFloat) -> Void = { _ in }

    let queueView: UIView
    let artworkView: UIView
    let lyricsView: UIView

    private let pagingScrollView: UIScrollView = {
        let scrollView = PagingScrollView()
        scrollView.backgroundColor = .clear
        scrollView.alwaysBounceHorizontal = true
        scrollView.alwaysBounceVertical = false
        scrollView.decelerationRate = .fast
        scrollView.delaysContentTouches = false
        scrollView.isDirectionalLockEnabled = true
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.isPagingEnabled = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.applySoftEdgeEffects()
        return scrollView
    }()

    private var pageViews: [Page: UIView] = [:]
    private var currentPage: Page = .artwork
    private var lastLayoutSize: CGSize = .zero
    private var isProgrammaticScrollInFlight = false

    init(
        queueView: UIView,
        artworkView: UIView,
        lyricsView: UIView,
    ) {
        self.queueView = queueView
        self.artworkView = artworkView
        self.lyricsView = lyricsView
        super.init(frame: UIScreen.main.bounds)
        backgroundColor = .clear
        installPagingScrollView()
        installPages()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutPagesIfNeeded()
    }

    func setSelector(
        _ selector: NowPlayingControlIslandViewModel.ContentSelector,
        animated: Bool,
    ) {
        let targetPage = page(for: selector)
        guard targetPage != currentPage else {
            if !isProgrammaticScrollInFlight {
                scrollToPage(targetPage, animated: false)
            }
            return
        }

        currentPage = targetPage
        scrollToPage(targetPage, animated: animated)
    }

    func ensureCurrentPageIsLaidOut() {
        layoutPagesIfNeeded(force: true)
    }

    private func installPagingScrollView() {
        pagingScrollView.delegate = self
        addSubview(pagingScrollView)
        pagingScrollView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    private func installPages() {
        for page in Page.allCases {
            let hostedView = hostedView(for: page)
            pagingScrollView.addSubview(hostedView)
            pageViews[page] = hostedView
        }
    }

    private func layoutPagesIfNeeded(force: Bool = false) {
        let size = pagingScrollView.bounds.size
        guard size.width > 0, size.height > 0 else {
            return
        }
        guard force || size != lastLayoutSize else {
            return
        }
        lastLayoutSize = size

        let pageWidth = size.width
        let pageHeight = size.height
        let pageCount = CGFloat(Page.allCases.count)
        pagingScrollView.contentSize = CGSize(width: pageWidth * pageCount, height: pageHeight)

        for page in Page.allCases {
            pageViews[page]?.frame = CGRect(
                x: pageWidth * CGFloat(page.rawValue),
                y: 0,
                width: pageWidth,
                height: pageHeight,
            )
        }

        scrollToPage(currentPage, animated: false)
    }

    private func hostedView(for page: Page) -> UIView {
        switch page {
        case .queue:
            queueView
        case .artwork:
            artworkView
        case .lyrics:
            lyricsView
        }
    }

    private func page(for selector: NowPlayingControlIslandViewModel.ContentSelector) -> Page {
        switch selector {
        case .queue:
            .queue
        case .artwork:
            .artwork
        case .lyrics:
            .lyrics
        }
    }

    private func selector(for page: Page) -> NowPlayingControlIslandViewModel.ContentSelector {
        switch page {
        case .queue:
            .queue
        case .artwork:
            .artwork
        case .lyrics:
            .lyrics
        }
    }

    private func scrollToPage(_ page: Page, animated: Bool) {
        let targetOffset = contentOffset(for: page)
        guard pagingScrollView.bounds.width > 0 else {
            return
        }

        if !animated {
            pagingScrollView.setContentOffset(targetOffset, animated: false)
            return
        }

        isProgrammaticScrollInFlight = true
        Interface.springAnimate(
            duration: Animation.duration,
            dampingRatio: Animation.damping,
            initialVelocity: Animation.initialVelocity,
        ) {
            self.pagingScrollView.contentOffset = targetOffset
        } completion: { [weak self] _ in
            self?.isProgrammaticScrollInFlight = false
            self?.settleVisiblePageIfNeeded(notifyChange: false)
        }
    }

    private func contentOffset(for page: Page) -> CGPoint {
        CGPoint(x: CGFloat(page.rawValue) * pagingScrollView.bounds.width, y: 0)
    }

    private func page(for offsetX: CGFloat) -> Page {
        guard pagingScrollView.bounds.width > 0 else {
            return currentPage
        }
        let rawIndex = Int(round(offsetX / pagingScrollView.bounds.width))
        let clampedIndex = min(max(rawIndex, 0), Page.allCases.count - 1)
        return Page(rawValue: clampedIndex) ?? currentPage
    }

    private func pageIndex(forProposedOffset proposedOffsetX: CGFloat, velocityX: CGFloat) -> Int {
        let maxIndex = Page.allCases.count - 1
        guard pagingScrollView.bounds.width > 0 else {
            return currentPage.rawValue
        }

        if abs(velocityX) > 0.24 {
            let steppedIndex = currentPage.rawValue + (velocityX > 0 ? 1 : -1)
            return min(max(steppedIndex, 0), maxIndex)
        }

        let roundedIndex = Int(round(proposedOffsetX / pagingScrollView.bounds.width))
        return min(max(roundedIndex, 0), maxIndex)
    }

    private func settleVisiblePageIfNeeded(notifyChange: Bool) {
        let visiblePage = page(for: pagingScrollView.contentOffset.x)
        guard visiblePage != currentPage else {
            return
        }

        currentPage = visiblePage
        if notifyChange {
            onPageChanged(selector(for: visiblePage))
        }
    }
}

extension NowPlayingPagingSectionView: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === pagingScrollView else { return }
        let pageWidth = scrollView.bounds.width
        guard pageWidth > 0 else { return }
        let artworkOffsetX = CGFloat(Page.artwork.rawValue) * pageWidth
        let distance = min(abs(scrollView.contentOffset.x - artworkOffsetX) / pageWidth, 1)
        onArtworkPageDistance(distance)
    }

    func scrollViewWillEndDragging(
        _ scrollView: UIScrollView,
        withVelocity velocity: CGPoint,
        targetContentOffset: UnsafeMutablePointer<CGPoint>,
    ) {
        guard scrollView === pagingScrollView else {
            return
        }
        let targetIndex = pageIndex(
            forProposedOffset: targetContentOffset.pointee.x,
            velocityX: velocity.x,
        )
        targetContentOffset.pointee = CGPoint(
            x: CGFloat(targetIndex) * scrollView.bounds.width,
            y: 0,
        )
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard scrollView === pagingScrollView, !decelerate, !isProgrammaticScrollInFlight else {
            return
        }
        settleVisiblePageIfNeeded(notifyChange: true)
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        guard scrollView === pagingScrollView, !isProgrammaticScrollInFlight else {
            return
        }
        settleVisiblePageIfNeeded(notifyChange: true)
    }
}
