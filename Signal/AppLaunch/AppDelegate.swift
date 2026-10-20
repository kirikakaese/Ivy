//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import UIKit

/// Receives app-wide lifecycle events from UIKit, and forwards them to
/// ``AppLifecycleManager``.
///
/// Events tied to the app's UI arrive in ``SceneDelegate`` instead.
@main
final class AppDelegate: UIResponder, UIApplicationDelegate {

    private let lifecycleManager = AppLifecycleManager.shared

    // MARK: - Lifecycle

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil,
    ) -> Bool {
        IvyMenuIcons.install() // Ivy: icons of the same size in Mac menus
        return lifecycleManager.didFinishLaunching(launchOptions: launchOptions)
    }

    // Ivy: chats open in their own windows; everything else is the main window.
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions,
    ) -> UISceneConfiguration {
        let isChatWindow = options.userActivities.contains { $0.activityType == IvyChatWindows.activityType }
        return UISceneConfiguration(
            name: isChatWindow ? IvyChatWindows.configurationName : "Default Configuration",
            sessionRole: connectingSceneSession.role,
        )
    }

    func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
        lifecycleManager.didReceiveMemoryWarning()
    }

    /// UIKit generally prefers `SceneDelegate.sceneDidDisconnect(_:)` for
    /// scene-based apps, which also calls through to the manager.
    func applicationWillTerminate(_ application: UIApplication) {
        lifecycleManager.willTerminate()
    }

    // MARK: - Orientation

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?,
    ) -> UIInterfaceOrientationMask {
        return lifecycleManager.supportedInterfaceOrientations(for: window)
    }

    // MARK: - Notifications

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        lifecycleManager.didRegisterForRemoteNotifications(deviceToken: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        lifecycleManager.didFailToRegisterForRemoteNotifications(error: error)
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void,
    ) {
        lifecycleManager.didReceiveRemoteNotification(userInfo, completionHandler: completionHandler)
    }

    // MARK: - Menus

    // Ivy: Ivy's commands in the Mac's menus
    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)
        #if targetEnvironment(macCatalyst)
        IvyKeyCommands.build(builder)
        #endif
    }
}
