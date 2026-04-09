import UIKit

@objc(SceneDelegate)
class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var environment: AppEnvironment?

    func scene(
        _ scene: UIScene, willConnectTo _: UISceneSession,
        options _: UIScene.ConnectionOptions
    ) {
        guard let windowScene = (scene as? UIWindowScene) else {
            AppLog.warning(
                self,
                "Scene is not a UIWindowScene (actual type: \(type(of: scene))) - aborting window setup"
            )
            return
        }
        let window = UIWindow(windowScene: windowScene)
        defer {
            window.makeKeyAndVisible()
            self.window = window
        }
        window.tintColor = .accent
        let bootController = BootProgressController()
        bootController.onBootComplete = { [weak self, weak window] environment in
            guard let self, let window else {
                return
            }
            self.environment = environment
            window.rootViewController = TabBarController(environment: environment)
            Task { @MainActor [environment] in
                _ = await environment.playbackController.restorePersistedPlaybackIfNeeded()
                environment.downloadManager.reconcileOnLaunch()
            }
        }
        window.rootViewController = bootController
    }

    func sceneWillResignActive(_: UIScene) {
        environment?.playbackController.setUIPublishingSuspended(true)
        environment?.playbackController.persistPlaybackState()
    }

    func sceneDidBecomeActive(_: UIScene) {
        environment?.playbackController.setUIPublishingSuspended(false)
    }

    func sceneDidEnterBackground(_: UIScene) {
        environment?.playbackController.persistPlaybackState()
    }

    func sceneDidDisconnect(_: UIScene) {
        environment?.playbackController.setUIPublishingSuspended(true)
        environment?.playbackController.persistPlaybackState()
    }
}
