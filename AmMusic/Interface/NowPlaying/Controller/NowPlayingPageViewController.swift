import AmMusicPlayerKit
import AVKit
import SnapKit
import Then
import UIKit

private enum NowPlayingPageAnimation {
    static let duration: TimeInterval = 0.9
    static let damping: CGFloat = 1.02
    static let initialVelocity: CGFloat = 0.78
}

private final class NowPlayingPageScrollView: UIScrollView {
    override func touchesShouldCancel(in _: UIView) -> Bool {
        true
    }
}

final class NowPlayingPageViewController: UIViewController {
    private enum Page: Int, CaseIterable {
        case queue
        case artwork
        case lyrics
    }

    private let listSectionView = NowPlayingListSectionView()
    private let centerSectionView = NowPlayingCenterSectionView()
    private let lyricSectionView = NowPlayingLyricSectionView()

    private let pagingScrollView = NowPlayingPageScrollView().then {
        $0.backgroundColor = .clear
        $0.alwaysBounceHorizontal = true
        $0.alwaysBounceVertical = false
        $0.decelerationRate = .fast
        $0.delaysContentTouches = false
        $0.isDirectionalLockEnabled = true
        $0.contentInsetAdjustmentBehavior = .never
        $0.isPagingEnabled = true
        $0.showsHorizontalScrollIndicator = false
        $0.showsVerticalScrollIndicator = false
    }

    private var pageViews: [Page: UIView] = [:]

    private var currentPage: Page = .artwork
    private var lastLayoutSize: CGSize = .zero
    private var isProgrammaticScrollInFlight = false
    var onPageChanged: ((NowPlayingControlIslandViewModel.ContentSelector) -> Void)?

    var onToggleQueueShuffle: (() -> Void)? {
        didSet {
            listSectionView.onToggleShuffle = onToggleQueueShuffle
        }
    }

    var onCycleQueueRepeatMode: (() -> Void)? {
        didSet {
            listSectionView.onCycleRepeatMode = onCycleQueueRepeatMode
        }
    }

    var onSelectQueueTrack: ((NowPlayingQueueTrackSelection) -> Void)? {
        didSet {
            listSectionView.onSelectQueueTrack = onSelectQueueTrack
        }
    }

    var onRemoveQueueTrack: ((Int) -> Void)? {
        didSet {
            listSectionView.onRemoveQueueTrack = onRemoveQueueTrack
        }
    }

    var onSeekToLyricsTime: ((TimeInterval) -> Void)? {
        didSet {
            lyricSectionView.onSeekToLineTime = onSeekToLyricsTime
        }
    }

    var onCopyAllLyrics: (([String]) -> Void)? {
        didSet {
            lyricSectionView.onCopyAllLyrics = onCopyAllLyrics
        }
    }

    var onManageLyrics: ((_ lyrics: [String], _ activeIndex: Int?) -> Void)? {
        didSet {
            lyricSectionView.onRequestManageLyrics = onManageLyrics
        }
    }

    var onArtworkLoaded: ((URL, UIImage) -> Void)? {
        didSet {
            centerSectionView.onArtworkLoaded = onArtworkLoaded
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        installPagingScrollView()
        installPages()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutPagesIfNeeded()
    }

    func bindTransport(to viewModel: NowPlayingControlIslandViewModel) {
        centerSectionView.bindTransport(to: viewModel)
    }

    func configureTransport(
        with content: NowPlayingControlIslandViewModel.Content,
        animated: Bool
    ) {
        centerSectionView.configureTransport(with: content, animated: animated)
    }

    func installRoutePickerView(_ routePickerView: AVRoutePickerView) {
        centerSectionView.installRoutePickerView(routePickerView)
    }

    func setSelector(
        _ selector: NowPlayingControlIslandViewModel.ContentSelector,
        animated: Bool
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

    func updateArtwork(url: URL?) {
        centerSectionView.updateArtwork(url: url)
    }

    func updateQueue(
        queue: [PlaybackTrack],
        playerIndex: Int?,
        repeatMode: RepeatMode,
        animatingDifferences: Bool = false
    ) {
        listSectionView.updateQueue(
            queue: queue,
            playerIndex: playerIndex,
            repeatMode: repeatMode,
            animatingDifferences: animatingDifferences
        )
    }

    func setQueueShuffleFeedbackActive(_ isActive: Bool) {
        listSectionView.setShuffleFeedbackActive(isActive)
    }

    func updateLyrics(text: String?, isLoading: Bool, currentTime: TimeInterval) {
        lyricSectionView.updateLyrics(text: text, isLoading: isLoading, currentTime: currentTime)
    }

    func updateCurrentLyricLine(_ line: String?) {
        centerSectionView.updateCurrentLyricLine(line)
    }

    func setInterfaceSuspended(_ suspended: Bool) {
        centerSectionView.setAnimationsSuspended(suspended)
        lyricSectionView.setAnimationSuspended(suspended)
    }

    func ensureCurrentPageIsLaidOut() {
        layoutPagesIfNeeded(force: true)
    }

    // MARK: - Page Layout (manual frame)

    private func installPagingScrollView() {
        pagingScrollView.delegate = self
        view.addSubview(pagingScrollView)
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
        guard size.width > 0, size.height > 0 else { return }
        guard force || size != lastLayoutSize else { return }
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
                height: pageHeight
            )
        }

        scrollToPage(currentPage, animated: false)
    }

    // MARK: - Page Navigation

    private func hostedView(for page: Page) -> UIView {
        switch page {
        case .queue: listSectionView
        case .artwork: centerSectionView
        case .lyrics: lyricSectionView
        }
    }

    private func page(for selector: NowPlayingControlIslandViewModel.ContentSelector) -> Page {
        switch selector {
        case .queue: .queue
        case .artwork: .artwork
        case .lyrics: .lyrics
        }
    }

    private func selector(for page: Page) -> NowPlayingControlIslandViewModel.ContentSelector {
        switch page {
        case .queue: .queue
        case .artwork: .artwork
        case .lyrics: .lyrics
        }
    }

    private func scrollToPage(_ page: Page, animated: Bool) {
        let targetOffset = contentOffset(for: page)
        guard pagingScrollView.bounds.width > 0 else { return }

        if !animated {
            pagingScrollView.setContentOffset(targetOffset, animated: false)
            return
        }

        isProgrammaticScrollInFlight = true
        InterfaceAnimation.springAnimate(
            duration: NowPlayingPageAnimation.duration,
            dampingRatio: NowPlayingPageAnimation.damping,
            initialVelocity: NowPlayingPageAnimation.initialVelocity
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
        guard pagingScrollView.bounds.width > 0 else { return currentPage }
        let rawIndex = Int(round(offsetX / pagingScrollView.bounds.width))
        let clampedIndex = min(max(rawIndex, 0), Page.allCases.count - 1)
        return Page(rawValue: clampedIndex) ?? currentPage
    }

    private func pageIndex(forProposedOffset proposedOffsetX: CGFloat, velocityX: CGFloat) -> Int {
        let maxIndex = Page.allCases.count - 1
        guard pagingScrollView.bounds.width > 0 else { return currentPage.rawValue }

        if abs(velocityX) > 0.24 {
            let steppedIndex = currentPage.rawValue + (velocityX > 0 ? 1 : -1)
            return min(max(steppedIndex, 0), maxIndex)
        }

        let roundedIndex = Int(round(proposedOffsetX / pagingScrollView.bounds.width))
        return min(max(roundedIndex, 0), maxIndex)
    }

    private func settleVisiblePageIfNeeded(notifyChange: Bool) {
        let visiblePage = page(for: pagingScrollView.contentOffset.x)
        guard visiblePage != currentPage else { return }

        currentPage = visiblePage
        if notifyChange {
            onPageChanged?(selector(for: visiblePage))
        }
    }
}

extension NowPlayingPageViewController: UIScrollViewDelegate {
    func scrollViewWillEndDragging(
        _ scrollView: UIScrollView,
        withVelocity velocity: CGPoint,
        targetContentOffset: UnsafeMutablePointer<CGPoint>
    ) {
        guard scrollView === pagingScrollView else { return }
        let targetIndex = pageIndex(
            forProposedOffset: targetContentOffset.pointee.x,
            velocityX: velocity.x
        )
        targetContentOffset.pointee = CGPoint(
            x: CGFloat(targetIndex) * scrollView.bounds.width,
            y: 0
        )
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard scrollView === pagingScrollView, !decelerate, !isProgrammaticScrollInFlight else { return }
        settleVisiblePageIfNeeded(notifyChange: true)
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        guard scrollView === pagingScrollView, !isProgrammaticScrollInFlight else { return }
        settleVisiblePageIfNeeded(notifyChange: true)
    }
}
