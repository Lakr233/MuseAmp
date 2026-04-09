import UIKit

enum SearchHighlightHelper {
    static func attributedString(
        text: String,
        query: String,
        font: UIFont,
        color: UIColor,
        highlightColor: UIColor = .tintColor
    ) -> NSAttributedString {
        let attributed = NSMutableAttributedString(
            string: text,
            attributes: [.font: font, .foregroundColor: color]
        )
        guard !query.isEmpty else { return attributed }

        let highlightFont = UIFont.systemFont(ofSize: font.pointSize, weight: .semibold)
        let lowerText = text.lowercased() as NSString
        let lowerQuery = query.lowercased()
        var searchStart = 0

        while searchStart < lowerText.length {
            let range = lowerText.range(
                of: lowerQuery,
                range: NSRange(location: searchStart, length: lowerText.length - searchStart)
            )
            guard range.location != NSNotFound else { break }
            attributed.addAttributes(
                [.font: highlightFont, .foregroundColor: highlightColor],
                range: range
            )
            searchStart = range.location + range.length
        }

        return attributed
    }
}
