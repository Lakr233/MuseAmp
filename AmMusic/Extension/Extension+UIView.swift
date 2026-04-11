//
//  Extension+UIView.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import UIKit

extension UIView {
    func removeAnimationsRecursively() {
        layer.removeAllAnimations()
        for subview in subviews {
            subview.removeAnimationsRecursively()
        }
    }
}
