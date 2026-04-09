import UIKit

extension UIView {
    func removeAnimationsRecursively() {
        layer.removeAllAnimations()
        for subview in subviews {
            subview.removeAnimationsRecursively()
        }
    }
}
