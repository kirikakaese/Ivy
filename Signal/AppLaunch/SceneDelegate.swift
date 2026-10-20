//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import UIKit

/// Receives scene lifecycle events from UIKit, and forwards them to
/// ``AppLifecycleManager``.
///
/// The app declares a single scene, so this is the only place UI-adjacent
/// lifecycle events arrive; app-wide events go to ``AppDelegate``.
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    private let lifecycleManager = AppLifecycleManager.shared

    var window: UIWindow?

    // MARK: - Lifecycle

    // Matches the deprecation on `handle(userActivity:)`, called below, so
    // it doesn't warn. Neither is actually deprecated.
    @available(iOS, deprecated: 13.0)
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions,
    ) {
        guard let windowScene = scene as? UIWindowScene else {
            owsFailDebug("Unexpected scene type: \(type(of: scene))")
            return
        }

        // Ivy: Ivy has one main window; chats get windows of their own.
        if Self.ivyHasMainWindow {
            UIApplication.shared.requestSceneSessionDestruction(session, options: nil)
            return
        }
        Self.ivyHasMainWindow = true

        self.window = lifecycleManager.connectUI(in: windowScene)

        // These arrive in the connection options rather than via the callbacks
        // below when they're what caused the scene to connect.
        for urlContext in connectionOptions.urlContexts {
            Logger.info("Connected to open a URL.")
            _ = lifecycleManager.handleOpenUrl(urlContext.url)
        }
        for userActivity in connectionOptions.userActivities {
            Logger.info("Connected to continue \(userActivity.activityType).")
            _ = lifecycleManager.handle(userActivity: userActivity)
        }
        if let shortcutItem = connectionOptions.shortcutItem {
            Logger.info("Connected to perform \(shortcutItem.type).")
            lifecycleManager.performAction(for: shortcutItem, completionHandler: { _ in })
        }
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        guard window != nil else {
            return // Ivy: a second main window that was turned away
        }
        Self.ivyHasMainWindow = false // Ivy
        lifecycleManager.disconnectUI()
    }

    /// Ivy: whether the main window is connected.
    private static var ivyHasMainWindow = false

    func sceneWillEnterForeground(_ scene: UIScene) {
        guard window != nil else { return } // Ivy: not a turned-away second main window
        lifecycleManager.willEnterForeground()
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        guard window != nil else { return } // Ivy: not a turned-away second main window
        lifecycleManager.didBecomeActive()
    }

    func sceneWillResignActive(_ scene: UIScene) {
        guard window != nil else { return } // Ivy: not a turned-away second main window
        lifecycleManager.willResignActive()
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        guard window != nil else { return } // Ivy: not a turned-away second main window
        lifecycleManager.didEnterBackground()
    }

    // MARK: - Handoff

    // Matches the deprecation on `handle(userActivity:)`, so that calling it
    // doesn't warn. Neither is actually deprecated.
    @available(iOS, deprecated: 13.0)
    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        _ = lifecycleManager.handle(userActivity: userActivity)
    }

    // MARK: - Shortcut Items

    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void,
    ) {
        Logger.info("\(shortcutItem.type)")
        lifecycleManager.performAction(for: shortcutItem, completionHandler: completionHandler)
    }

    // MARK: - URL Handling

    func scene(_ scene: UIScene, openURLContexts urlContexts: Set<UIOpenURLContext>) {
        Logger.info("")
        for urlContext in urlContexts {
            _ = lifecycleManager.handleOpenUrl(urlContext.url)
        }
    }
}
