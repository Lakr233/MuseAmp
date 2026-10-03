@testable import MuseAmp
import Testing
import UIKit

@Suite(.serialized)
@MainActor
struct NowPlayingCenterSectionLayoutTests {
    /// Left-column sizes of the relaxed Now Playing layout: a 1000x600 Mac
    /// window, the minimum Mac window, and a shorter iPad window.
    @Test(arguments: [
        CGSize(width: 633.5, height: 780),
        CGSize(width: 568.5, height: 651),
        CGSize(width: 500, height: 560),
    ])
    func `A short relaxed column shrinks the artwork instead of the title or time rows`(
        columnSize: CGSize,
    ) async throws {
        let sandbox = TestLibrarySandbox()
        let environment = sandbox.makeEnvironment()
        let transportView = NowPlayingRelaxedTransportView(environment: environment)
        let centerSectionView = NowPlayingCenterSectionView(
            environment: environment,
            transportContentView: transportView,
        )

        // A real cover is larger than its slot, so the image view's intrinsic
        // size pushes back against shrinking the artwork.
        let artworkView = try #require(
            centerSectionView.avatarSectionView.subviews.compactMap { $0 as? MuseAmpImageView }.first,
        )
        artworkView.setImage(makeCoverImage(sideLength: 600))

        let timeLabels = labels(in: transportView.playbackTimeRowView)
        #expect(timeLabels.count == 2)
        try await waitUntilTextIsSet(on: timeLabels)

        centerSectionView.frame = CGRect(origin: .zero, size: columnSize)
        centerSectionView.layoutIfNeeded()

        for label in timeLabels + labels(in: transportView.titleView) {
            #expect(label.bounds.height >= label.intrinsicContentSize.height)
        }

        let artworkFrame = centerSectionView.avatarSectionView.convert(
            centerSectionView.avatarSectionView.bounds,
            to: centerSectionView,
        )
        let transportFrame = transportView.convert(transportView.bounds, to: centerSectionView)
        #expect(transportFrame.minY >= artworkFrame.maxY)
        #expect(transportFrame.maxY <= columnSize.height)
    }
}

private func labels(in view: UIView) -> [UILabel] {
    view.subviews.flatMap { subview -> [UILabel] in
        if let label = subview as? UILabel {
            return [label]
        }
        return labels(in: subview)
    }
}

private func waitUntilTextIsSet(on labels: [UILabel]) async throws {
    let deadline = Date().addingTimeInterval(2)
    while labels.contains(where: { ($0.text ?? "").isEmpty }), Date() < deadline {
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(labels.allSatisfy { !($0.text ?? "").isEmpty })
}

private func makeCoverImage(sideLength: CGFloat) -> UIImage {
    let size = CGSize(width: sideLength, height: sideLength)
    return UIGraphicsImageRenderer(size: size).image { context in
        UIColor.systemPurple.setFill()
        context.fill(CGRect(origin: .zero, size: size))
    }
}
