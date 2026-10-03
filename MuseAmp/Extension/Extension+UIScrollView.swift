//
//  Extension+UIScrollView.swift
//  MuseAmp
//
//  Created by @Lakr233 on 2026/10/03.
//

import UIKit

extension UIScrollView {
    /// Gives every edge effect that is still shown the soft style. A hidden
    /// edge effect is left alone, so it stays hidden.
    func applySoftEdgeEffects() {
        guard #available(iOS 26.0, tvOS 26.0, *) else { return }
        let edgeEffects = [topEdgeEffect, leftEdgeEffect, bottomEdgeEffect, rightEdgeEffect]
        for edgeEffect in edgeEffects where !edgeEffect.isHidden {
            edgeEffect.style = .soft
        }
    }
}
