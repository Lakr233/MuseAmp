import UIKit

enum MenuSectionProvider {
    static func inline(_ children: [UIMenuElement]) -> UIMenu? {
        guard !children.isEmpty else {
            return nil
        }

        return UIMenu(options: .displayInline, children: children)
    }
}
