//
//  MenuSectionProvider.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import UIKit

enum MenuSectionProvider {
    static func inline(_ children: [UIMenuElement]) -> UIMenu? {
        guard !children.isEmpty else {
            return nil
        }

        return UIMenu(options: .displayInline, children: children)
    }
}
