import UIKit

enum InterfaceStyle {
    enum Spacing {
        static let xSmall: CGFloat = 8
        static let small: CGFloat = 16
        static let medium: CGFloat = 24
        static let large: CGFloat = 32
        static let xLarge: CGFloat = 40
    }

    enum Insets {
        static func all(_ value: CGFloat) -> UIEdgeInsets {
            UIEdgeInsets(top: value, left: value, bottom: value, right: value)
        }

        static func symmetric(vertical: CGFloat, horizontal: CGFloat) -> UIEdgeInsets {
            UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
        }
    }
}
