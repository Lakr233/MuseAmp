@testable import MuseAmp
import Testing
import UIKit

@Suite(.serialized)
@MainActor
struct TrackNumberBadgeTests {
    private let pointSize: CGFloat = 15

    @Test
    func `every track number from 1 to 1000 gets a badge`() {
        let missing = (1 ... 1000).filter {
            TrackNumberBadge.rendering(for: $0, pointSize: pointSize) == nil
        }
        #expect(missing.isEmpty, "no badge for \(missing)")
    }

    @Test
    func `numbers 1 to 50 keep the system symbol`() throws {
        for number in [1, 9, 10, 50] {
            let badge = try #require(TrackNumberBadge.rendering(for: number, pointSize: pointSize))
            #expect(badge.image.isSymbolImage)
            #expect(badge.widthRatio == 1)
        }
    }

    @Test
    func `numbers past 50 match the symbol circle`() throws {
        let symbol = try #require(TrackNumberBadge.rendering(for: 50, pointSize: pointSize))
        for number in [51, 60, 99] {
            let badge = try #require(TrackNumberBadge.rendering(for: number, pointSize: pointSize))
            #expect(!badge.image.isSymbolImage)
            #expect(abs(badge.widthRatio - 1) < 0.001)
            #expect(abs(badge.image.size.height - symbol.image.size.height) < 0.01)
            #expect(abs(badge.image.size.width - symbol.image.size.width) < 0.01)
            #expect(badge.image.renderingMode == .alwaysTemplate)
            let symbolBaseline = try #require(symbol.image.baselineOffsetFromBottom)
            let badgeBaseline = try #require(badge.image.baselineOffsetFromBottom)
            #expect(abs(badgeBaseline - symbolBaseline) < 0.01)
        }
    }

    @Test
    func `three digit numbers widen into a capsule of the same height`() throws {
        let circle = try #require(TrackNumberBadge.rendering(for: 99, pointSize: pointSize))
        let hundred = try #require(TrackNumberBadge.rendering(for: 100, pointSize: pointSize))
        let thousand = try #require(TrackNumberBadge.rendering(for: 1000, pointSize: pointSize))

        #expect(hundred.widthRatio > 1)
        #expect(thousand.widthRatio > hundred.widthRatio)
        #expect(abs(hundred.image.size.height - circle.image.size.height) < 0.01)
        #expect(abs(hundred.image.size.width - circle.image.size.width * hundred.widthRatio) < 0.01)
    }

    @Test
    func `drawn badges read their number to VoiceOver`() throws {
        let badge = try #require(TrackNumberBadge.rendering(for: 51, pointSize: pointSize))
        let expected = NumberFormatter.localizedString(from: 51, number: .none)
        #expect(badge.image.accessibilityLabel == expected)
    }
}
