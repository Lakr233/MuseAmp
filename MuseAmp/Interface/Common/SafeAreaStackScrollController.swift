//
//  SafeAreaStackScrollController.swift
//  MuseAmp
//
//  Created by @Lakr233 on 2026/11/18.
//

import ConfigurableKit
import UIKit

/// `StackScrollController` whose rows stay inside the view's left and right
/// safe area.
///
/// ConfigurableKit pins the stack to the scroll view's full width, and a
/// vertically scrolling scroll view never insets its content sideways. On the
/// iPhone Duo the status bar and the vertical navigation and tab bars sit in
/// a side safe area, so trailing values and controls were drawn under them.
/// The scroll view still spans the whole view; only the stack is narrowed.
class SafeAreaStackScrollController: StackScrollController {
    /// Declared so it stays nonisolated like the subclasses' own deinits;
    /// the synthesized one would take the module's main actor default.
    deinit {}

    override func viewDidLoad() {
        super.viewDidLoad()
        pinStackViewToSafeArea()
    }

    private func pinStackViewToSafeArea() {
        let horizontalEdges = contentView.constraints.filter { constraint in
            constraint.firstItem === stackView
                && constraint.secondItem === contentView
                && [.leading, .trailing].contains(constraint.firstAttribute)
        }
        // Leave ConfigurableKit's layout alone if it no longer pins the stack
        // to the content view's edges; adding guides would conflict with it.
        guard horizontalEdges.count == 2 else { return }
        NSLayoutConstraint.deactivate(horizontalEdges)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
        ])
    }
}
