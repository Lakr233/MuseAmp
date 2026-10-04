//
//  ConfirmationAlertPresenter.swift
//  MuseAmp
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
        onCancel: @escaping () -> Void = {},
        onConfirm: @escaping () -> Void,
    ) {
        let alert = AlertViewController(title: .init(title), message: .init(message)) { context in
            context.addAction(title: "Cancel") {
                context.dispose {
                    onCancel()
                }
            }
            context.addAction(title: .init(confirmTitle), attribute: confirmAttribute) {
                context.dispose {
                    onConfirm()
                }
            }
        }
        viewController.present(alert, animated: true)
    }
}
