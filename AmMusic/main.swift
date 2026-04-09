import UIKit

MainActor.assumeIsolated {
    AppLog.info("main", "Entering UIApplicationMain - argc: \(CommandLine.argc), delegate: \(NSStringFromClass(AppDelegate.self))")
    _ = UIApplicationMain(
        CommandLine.argc,
        CommandLine.unsafeArgv,
        nil,
        NSStringFromClass(AppDelegate.self)
    )

    AppLog.error("main", "UIApplicationMain returned unexpectedly - fatalError imminent")
    fatalError("UIApplicationMain returned unexpectedly.")
}
