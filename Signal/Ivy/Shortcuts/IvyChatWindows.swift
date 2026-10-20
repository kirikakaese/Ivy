//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

/// Chats in their own windows (Mac and iPad). A window remembers its chat
/// and comes back with it. Ivy's main window stays the only one with the
/// chat list.
enum IvyChatWindows {

    static let activityType = "org.ivy.chatWindow"
    static let configurationName = "Ivy Chat Window"
    private static let threadKey = "thread"

    /// Posted when Ivy locks, so chat windows cover themselves.
    static let ivyDidLock = Notification.Name("IvyDidLock")

    static var isAvailable: Bool {
        UIApplication.shared.supportsMultipleScenes
    }

    static var openInNewWindowTitle: String {
        IvyLocalizedString("CHAT_OPEN_IN_NEW_WINDOW", comment: "Context menu action that opens a chat in its own window.")
    }

    static func activity(threadUniqueId: String) -> NSUserActivity {
        let activity = NSUserActivity(activityType: activityType)
        activity.userInfo = [threadKey: threadUniqueId]
        return activity
    }

    static func threadUniqueId(of activity: NSUserActivity?) -> String? {
        guard activity?.activityType == activityType else {
            return nil
        }
        return activity?.userInfo?[threadKey] as? String
    }

    static func isChatWindow(_ session: UISceneSession) -> Bool {
        session.configuration.name == configurationName
    }

    /// The session of Ivy's main window.
    static var mainSession: UISceneSession? {
        UIApplication.shared.openSessions.first { !isChatWindow($0) }
    }

    /// Brings Ivy's main window to the front, reopening it if it was closed.
    static func activateMainWindow() {
        UIApplication.shared.requestSceneSessionActivation(mainSession, userActivity: nil, options: nil)
    }

    /// Opens a chat in its own window, or brings its window to the front.
    static func open(threadUniqueId: String) {
        let existing = UIApplication.shared.openSessions.first { session in
            isChatWindow(session) && Self.threadUniqueId(of: session.stateRestorationActivity) == threadUniqueId
        }
        UIApplication.shared.requestSceneSessionActivation(
            existing,
            userActivity: activity(threadUniqueId: threadUniqueId),
            options: nil,
        )
    }
}

/// The window of one chat.
@MainActor
final class IvyChatSceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?
    private var threadUniqueId: String?
    private var cover: UIView?
    private var coverTimer: Timer?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else {
            return
        }
        let threadUniqueId = IvyChatWindows.threadUniqueId(of: connectionOptions.userActivities.first)
            ?? IvyChatWindows.threadUniqueId(of: session.stateRestorationActivity)
        guard let threadUniqueId else {
            UIApplication.shared.requestSceneSessionDestruction(session, options: nil)
            return
        }
        self.threadUniqueId = threadUniqueId
        scene.userActivity = IvyChatWindows.activity(threadUniqueId: threadUniqueId)

        let window = UIWindow(windowScene: windowScene)
        let placeholder = UIViewController()
        placeholder.view.backgroundColor = .Signal.background
        window.rootViewController = placeholder
        window.makeKeyAndVisible()
        self.window = window
        #if targetEnvironment(macCatalyst)
        windowScene.sizeRestrictions?.minimumSize = CGSize(width: 380, height: 480)
        windowScene.titlebar?.titleVisibility = .visible
        #endif

        NotificationCenter.default.addObserver(self, selector: #selector(ivyDidLock), name: IvyChatWindows.ivyDidLock, object: nil)

        Task { @MainActor [weak self] in
            try? await AppLifecycleManager.shared.appReadiness.waitForAppReady()
            self?.showChat(in: windowScene, session: session)
        }
    }

    private func showChat(in windowScene: UIWindowScene, session: UISceneSession) {
        guard let threadUniqueId, let window else {
            return
        }
        let loaded: (ConversationViewController, String)? = SSKEnvironment.shared.databaseStorageRef.read { tx in
            guard let thread = DependenciesBridge.shared.threadStore.fetchThread(uniqueId: threadUniqueId, tx: tx) else {
                return nil
            }
            // Hidden chats only open while they are shown.
            if IvyHiddenChats.shared.isHidden(thread: thread), !IvyHiddenChats.shared.isRevealed {
                return nil
            }
            let threadViewModel = ThreadViewModel(threadUniqueId: threadUniqueId, forChatList: false, transaction: tx)
            let conversation = ConversationViewController.load(threadViewModel: threadViewModel, action: .none, focusMessageId: nil, tx: tx)
            return (conversation, SSKEnvironment.shared.contactManagerRef.displayName(for: thread, transaction: tx))
        }
        guard let (conversation, name) = loaded else {
            UIApplication.shared.requestSceneSessionDestruction(session, options: nil)
            return
        }
        windowScene.title = name
        window.rootViewController = OWSNavigationController(rootViewController: conversation)
        updateCover()
    }

    func stateRestorationActivity(for scene: UIScene) -> NSUserActivity? {
        scene.userActivity
    }

    // MARK: - Screen Lock

    func sceneDidBecomeActive(_ scene: UIScene) {
        updateCover()
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        if ScreenLock.shared.isScreenLockEnabled() {
            showCover()
        }
    }

    @objc
    private func ivyDidLock() {
        showCover()
    }

    private var isIvyLocked: Bool {
        ScreenLock.shared.isScreenLockEnabled() && AppEnvironment.shared.screenLockUI.ivyIsLocked
    }

    /// While Ivy is locked, chat windows show nothing of the chat; Ivy
    /// unlocks in its main window.
    private func updateCover() {
        if isIvyLocked {
            showCover()
        } else {
            cover?.removeFromSuperview()
            cover = nil
            coverTimer?.invalidate()
            coverTimer = nil
        }
    }

    private func showCover() {
        guard let window, cover == nil else {
            return
        }
        let cover = UIView()
        cover.backgroundColor = .Signal.background
        let icon = UIImageView(image: UIImage(systemName: "lock.fill"))
        icon.tintColor = .Signal.accent
        icon.contentMode = .center
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 40)
        var configuration = UIButton.Configuration.filled()
        configuration.title = IvyLocalizedString("CHAT_WINDOW_UNLOCK", comment: "Button in a locked chat window that goes to Ivy's main window to unlock.")
        configuration.baseBackgroundColor = .Signal.accent
        configuration.cornerStyle = .large
        let button = UIButton(configuration: configuration, primaryAction: UIAction { _ in
            IvyChatWindows.activateMainWindow()
        })
        let stack = UIStackView(arrangedSubviews: [icon, button])
        stack.axis = .vertical
        stack.spacing = 16
        stack.alignment = .center
        cover.addSubview(stack)
        stack.autoCenterInSuperview()
        window.addSubview(cover)
        cover.autoPinEdgesToSuperviewEdges()
        self.cover = cover
        // Ivy unlocks elsewhere; look again now and then.
        coverTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isIvyLocked, self.window?.windowScene?.activationState == .foregroundActive else { return }
                self.updateCover()
            }
        }
    }
}

extension ChatListViewController {

    /// "Open in New Window" for a chat's context menu, where windows exist.
    func ivyOpenInNewWindowAction(threadViewModel: ThreadViewModel) -> UIAction? {
        guard IvyChatWindows.isAvailable else {
            return nil
        }
        let threadId = threadViewModel.threadUniqueId
        return UIAction(title: IvyChatWindows.openInNewWindowTitle, image: UIImage(systemName: "macwindow.badge.plus")) { _ in
            IvyChatWindows.open(threadUniqueId: threadId)
        }
    }
}
