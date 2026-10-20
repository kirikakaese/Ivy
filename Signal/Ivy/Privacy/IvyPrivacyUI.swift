//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import LocalAuthentication
import SignalServiceKit
import SignalUI

/// Locking Ivy right away and showing hidden chats.
@MainActor
enum IvyPrivacy {

    private static var isStarted = false

    /// Called when the app is ready: hidden chats hide again whenever Ivy
    /// leaves the screen.
    static func start() {
        guard !isStarted else {
            return
        }
        isStarted = true
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main,
        ) { _ in
            IvyHiddenChats.shared.setRevealed(false)
            IvyLockedChats.shared.closeAll()
        }
    }

    static var lockTitle: String {
        IvyLocalizedString("LOCK_NOW", comment: "Menu command that locks Ivy right away.")
    }

    /// Locks Ivy, or explains how to turn on Screen Lock.
    static func lockNow(from viewController: UIViewController?) {
        IvyHiddenChats.shared.setRevealed(false)
        IvyLockedChats.shared.closeAll()
        guard !AppEnvironment.shared.screenLockUI.ivyLockNow() else {
            return
        }
        OWSActionSheets.showActionSheet(
            title: lockTitle,
            message: IvyLocalizedString("LOCK_NOW_NEEDS_SCREEN_LOCK", comment: "Shown when the user locks Ivy but Screen Lock is off."),
            fromViewController: viewController,
        )
    }

    /// Locks when Screen Lock is on, without asking anything. For the Mac's
    /// screen lock and sleep.
    static func lockIfEnabled() {
        IvyHiddenChats.shared.setRevealed(false)
        IvyLockedChats.shared.closeAll()
        AppEnvironment.shared.screenLockUI.ivyLockNow()
    }

    // MARK: - Hidden chats

    static var showHiddenTitle: String {
        IvyLocalizedString("HIDDEN_CHATS_SHOW", comment: "Menu action that shows the hidden chats after Face ID, Touch ID or the device passcode.")
    }

    static var hideHiddenTitle: String {
        IvyLocalizedString("HIDDEN_CHATS_HIDE", comment: "Menu action that hides the hidden chats again.")
    }

    /// Shows the hidden chats once the user proves it's them.
    static func revealHiddenChats() {
        let context = LAContext()
        let reason = IvyLocalizedString("HIDDEN_CHATS_UNLOCK_REASON", comment: "Shown by Face ID, Touch ID or the passcode prompt when showing hidden chats.")
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, error in
            if let error {
                Logger.info("Hidden chats stay hidden: \(error)")
            }
            guard success else {
                return
            }
            DispatchQueue.main.async {
                IvyHiddenChats.shared.setRevealed(true)
            }
        }
    }
}

// MARK: - Chat list

extension ChatListViewController {

    /// "Hide Chat" or "Show in Chat List" for a chat's context menu.
    func ivyHideChatAction(threadViewModel: ThreadViewModel) -> UIAction? {
        guard let chat = IvyChatReference(thread: threadViewModel.threadRecord) else {
            return nil
        }
        if IvyHiddenChats.shared.isHidden(chat) {
            return UIAction(
                title: IvyLocalizedString("HIDDEN_CHAT_UNHIDE", comment: "Context menu action that stops hiding a chat."),
                image: UIImage(systemName: "eye"),
            ) { _ in
                IvyHiddenChats.shared.unhide(chat)
            }
        }
        return UIAction(
            title: IvyLocalizedString("HIDDEN_CHAT_HIDE", comment: "Context menu action that hides a chat from the chat list."),
            image: UIImage(systemName: "eye.slash"),
        ) { [weak self] _ in
            IvyHiddenChats.shared.hide(chat)
            self?.presentToast(text: IvyLocalizedString(
                "HIDDEN_CHAT_HIDDEN_TOAST",
                comment: "Shown after hiding a chat. Explains how to show hidden chats.",
            ))
        }
    }

    /// The profile menu's "Show Hidden Chats" or "Hide Hidden Chats", and
    /// "Lock Ivy".
    func ivyPrivacyMenuActions() -> [UIAction] {
        var actions = [UIAction]()
        if !IvyHiddenChats.shared.isEmpty {
            if IvyHiddenChats.shared.isRevealed {
                actions.append(UIAction(title: IvyPrivacy.hideHiddenTitle, image: UIImage(systemName: "eye.slash")) { _ in
                    IvyHiddenChats.shared.setRevealed(false)
                })
            } else {
                actions.append(UIAction(title: IvyPrivacy.showHiddenTitle, image: UIImage(systemName: "eye")) { _ in
                    IvyPrivacy.revealHiddenChats()
                })
            }
        }
        if ScreenLock.shared.isScreenLockEnabled() {
            actions.append(UIAction(title: IvyPrivacy.lockTitle, image: UIImage(systemName: "lock")) { [weak self] _ in
                IvyPrivacy.lockNow(from: self)
            })
        }
        return actions
    }
}

// MARK: - Commands

extension ConversationSplitViewController {

    @objc
    func ivyLockNow() {
        IvyPrivacy.lockNow(from: self)
    }
}
