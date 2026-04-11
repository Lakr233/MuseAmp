//
//  ConfirmationAlertPresenter.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import AlertController
import UIKit

enum ConfirmationAlertPresenter {
    static func present(
        on viewController: UIViewController,
        title: String,
        message: String,
        confirmTitle: String,
        confirmAttribute: ActionContext.Action.Attribute = .accent,
        onConfirm: @escaping () -> Void,
    ) {
        let alert = AlertViewController(title: title, message: message) { context in
            context.addAction(title: String(localized: "Cancel")) {
                context.dispose()
            }
            context.addAction(title: confirmTitle, attribute: confirmAttribute) {
                context.dispose {
                    onConfirm()
                }
            }
        }
        viewController.present(alert, animated: true)
    }
}
