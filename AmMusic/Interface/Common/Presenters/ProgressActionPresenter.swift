//
//  ProgressActionPresenter.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import AlertController
import UIKit

enum ProgressActionPresenter {
    static func run<T>(
        on viewController: UIViewController,
        title: String,
        message: String,
        action: @escaping () async throws -> T,
        onSuccess: @MainActor @escaping (T) -> Void,
        onFailure: @MainActor @escaping (Error) -> Void,
    ) {
        let alert = AlertProgressIndicatorViewController(title: title, message: message)
        viewController.present(alert, animated: true)

        Task { [weak viewController, weak alert] in
            do {
                let result = try await action()
                await MainActor.run { [weak viewController, weak alert] in
                    alert?.dismiss(animated: true) {
                        guard let viewController else { return }
                        onSuccess(result)
                        _ = viewController
                    }
                }
            } catch {
                await MainActor.run { [weak viewController, weak alert] in
                    alert?.dismiss(animated: true) {
                        guard let viewController else { return }
                        onFailure(error)
                        _ = viewController
                    }
                }
            }
        }
    }

    static func run(
        on viewController: UIViewController,
        title: String,
        message: String,
        action: @escaping () async throws -> Void,
        completion: @MainActor @escaping () -> Void,
    ) {
        let alert = AlertProgressIndicatorViewController(title: title, message: message)
        viewController.present(alert, animated: true)

        Task { [weak viewController, weak alert] in
            do {
                try await action()
            } catch {
                AppLog.error("ProgressActionPresenter", "action failed: \(error.localizedDescription)")
            }

            await MainActor.run { [weak viewController, weak alert] in
                alert?.dismiss(animated: true) {
                    guard let viewController else { return }
                    completion()
                    _ = viewController
                }
            }
        }
    }
}
