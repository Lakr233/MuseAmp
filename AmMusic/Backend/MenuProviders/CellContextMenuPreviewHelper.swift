//
//  CellContextMenuPreviewHelper.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import UIKit

enum CellContextMenuPreviewHelper {
    static func targetedPreview(
        for configuration: UIContextMenuConfiguration,
        in tableView: UITableView,
        backgroundColor: UIColor = .secondarySystemBackground,
    ) -> UITargetedPreview? {
        guard let indexPath = configuration.identifier as? IndexPath,
              let cell = tableView.cellForRow(at: indexPath)
        else {
            return nil
        }

        let parameters = UIPreviewParameters()
        parameters.backgroundColor = backgroundColor
        parameters.visiblePath = UIBezierPath(
            roundedRect: cell.bounds,
            cornerRadius: 14,
        )
        return UITargetedPreview(view: cell, parameters: parameters)
    }
}
