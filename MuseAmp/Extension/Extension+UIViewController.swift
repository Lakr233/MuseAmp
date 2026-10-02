//
//  Extension+UIViewController.swift
//  MuseAmp
//
//  Created by @Lakr233 on 2026/10/03.
//

import UIKit

extension UIViewController {
    /// True while the controller is being popped, or dismissed together with
    /// the sheet that holds it. Read it in `viewDidDisappear`, which a
    /// cancelled swipe-back or sheet drag never reaches.
    var isLeavingNavigationStack: Bool {
        isMovingFromParent
            || isBeingDismissed
            || navigationController?.isBeingDismissed == true
    }
}
